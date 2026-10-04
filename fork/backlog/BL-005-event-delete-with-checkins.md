# BL-005: Deleting an event that has check-ins crashes

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-04 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/event-destroy-checkins` |
| Upstream issue / PR | none yet |

## Summary

Clicking **Delete** on an event that has any check-ins raises an error instead of deleting the event or explaining why it can't. The only way through is to check out every attendee first, one at a time, and nothing in the UI says so. We hit this in production on 2026-10-04 while merging a duplicate concessions event that had one check-in left on it.

## Where things are today (upstream `32e8023`)

- **No `dependent:` option:** `app/models/event.rb`, line 9: `has_many :checkins`. When an event is destroyed, Rails leaves its check-ins in place.
- **The database refuses:** `db/schema.rb`, line 777: `add_foreign_key "checkins", "events"`. Deleting an event row that check-ins still point to fails with `ActiveRecord::InvalidForeignKey` (PG::ForeignKeyViolation).
- **The controller doesn't handle it:** `app/controllers/events_controller.rb`, lines 72–75, calls `@event.destroy!` and redirects. The exception isn't rescued (`ApplicationController` only rescues `Pundit::NotAuthorizedError`, line 28), so the user gets an error page.
- **The button gives no warning:** `app/views/events/show.html.erb`, line 34: the Delete button's confirm text is a plain "Are you sure?", with no mention of check-ins.
- **Check-ins already clean up after themselves:** `app/models/checkin.rb`, line 7: `has_many :checkin_field_responses, dependent: :destroy`. Removing a check-in also removes its field responses.
- **No test covers this:** `test/controllers/events_controller_test.rb` has no destroy test. The fixtures put a check-in on each event (`test/fixtures/checkins.yml`, `one` → event `one`), so a destroy test against those fixtures would reproduce the crash right away.
- **The same problem with event types:** `app/models/event_type.rb`, line 4: `has_many :events` has no `dependent:` either, against FK `events → event_types` (schema line 779). `event_types_controller.rb`, line 47 has the same unrescued `destroy!`. Fix both together, or make event types a follow-up.

## Proposed fix

Make deletion work, and make its consequences visible before the click:

1. **Model:** `has_many :checkins, dependent: :destroy` on `Event`. Each check-in is destroyed through ActiveRecord, so its field responses go with it, each record gets an `AuditLog` "destroy" entry (both models have `has_paper_trail`), and `checkins - destroy` hooks fire. Every removed check-in can be restored from the audit log.
2. **Confirm text:** when the event has check-ins, the Delete button's confirm says so: "Delete this event and its N check-ins?"
3. **Controller:** wrap `destroy!` so an unexpected failure redirects back to the event with a flash error instead of an error page.

### Alternative: block deletion

Use `dependent: :restrict_with_error` and show "This event has N check-ins. Check them out before deleting it." This is safer if upstream treats check-ins as permanent attendance history, but it keeps the one-by-one checkout chore. Ask upstream which they prefer. Either one fixes the crash.

For `EventType`, prefer `restrict_with_error`. Deleting a type that still has events would cascade much further.

## Hooks

The only change is that existing hooks start firing. With `dependent: :destroy`, `checkins - destroy` and `checkin_field_responses - destroy` run for every removed check-in, through the existing `CanBeHooked` callbacks (`app/models/concerns/can_be_hooked.rb`), before `events - destroy` runs. That's the right behavior: integrations that watch check-ins hear about the removals. Today those hooks never fire, because the delete fails. No new catalog entries needed. With the restrict alternative, nothing changes for hooks.

## Tests

- `EventsControllerTest`: deleting an event that has check-ins (the fixture's event `one`) succeeds, removes its check-ins and their field responses, and redirects to the calendar.
- Model test: destroying an event creates an `AuditLog` destroy entry for each check-in.
- View test: the confirm text includes the check-in count when there are any, and stays "Are you sure?" when there are none.
- With the restrict alternative: deleting fails, redirects back with the flash message, and leaves everything in place.
- If event types are included, the matching tests for `EventTypesController#destroy`.

## Fork strategy notes

- This is a generic upstream bug and small enough for a direct PR after a short issue. Don't carry it in the fork unless upstream declines.
- No migration needed: the foreign keys stay as they are. No flag needed: it fixes a crash.
- Until it's fixed, the workaround in production is to check out each attendee on the event's page, then delete the event.

## Draft upstream issue

> **Deleting an event with check-ins raises an error**
>
> `Event has_many :checkins` has no `dependent:` option, and `checkins.event_id` has a foreign key, so `EventsController#destroy` hits `ActiveRecord::InvalidForeignKey` whenever the event has any check-ins. The user sees an error page, and the only workaround is checking out every attendee first. Proposal: `dependent: :destroy` (field responses already cascade from check-ins, and each removal is audit-logged), plus a confirm message that states how many check-ins will be deleted. If you'd rather check-ins block deletion, `restrict_with_error` with a clear message works too. `EventType` → `events` has the same issue. Happy to send a PR for either approach.
