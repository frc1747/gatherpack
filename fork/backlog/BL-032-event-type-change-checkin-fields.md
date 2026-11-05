# BL-032: Changing an event's type doesn't update its check-ins' fields

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | waiting |
| Added | 2026-11-04 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Planned branch | none yet |
| Upstream issue / PR | none |

## Summary

When an event's type changes, `Event#update_checkins` is meant to call `refresh_fields` on each check-in: add blank responses for the new type's check-in fields and remove the old type's. It never runs, so check-ins keep the old type's responses and lack the new type's. The next thing that calls `refresh_fields` (opening Arrange, Print, or a check-in's edit form) then quietly deletes the old answers. Until that happens, the old type can't be deleted because its fields still have responses (BL-031). Found 2026-11-04 in review of BL-031.

## Where things are (upstream `3fa5700`)

- `app/models/event.rb:56-60`: `update_checkins` runs `if event_type_id_changed?`. It's an `after_update` callback, where Rails has already moved the change to `saved_changes`, so `event_type_id_changed?` is false. `saved_change_to_event_type_id?` is the check it needs (confirmed in review).

## Decide before fixing

Fixing the condition makes a type change delete the old type's answers right away, for every check-in. That's the intended design, but it destroys data on a dropdown change. Options: fix it as intended (and say so in the event form when the type changes and check-ins have answers), or keep the answers and only add the new type's fields. Ask upstream which they mean.

## Decision (2026-11-05): keep the answers

Keep the old type's answers so switching the type back restores them. They aren't orphans: each still belongs to its check-in and to a field of the old type.

- Fix the condition (`saved_change_to_event_type_id?`) so the new type's blank responses are added on a type change.
- Stop `Checkin#refresh_fields` deleting responses for fields not on the current type (today it uses `delete`, which skips the audit log, so they can't be recovered). Screens that list responses (check-in form, Arrange, Print, exports) show only the current type's fields.
- Old answers go only when the old event type is deleted (BL-031 asks first).
- Ask upstream which they intended before proposing it there.

## Hooks

`checkin_field_responses - create/destroy` would fire for the added and removed responses.

## Tests

- Changing the type of an event with check-ins adds the new type's fields to each check-in, and handles the old ones per the decision.
- No change of type: nothing happens.

## Fork strategy notes

One-line upstream fix plus the decision above. Confirm with Corey before any issue or PR.
