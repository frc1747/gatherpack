# BL-006: Events with no team are hidden from everyone but admins

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | blocked |
| Added | 2026-10-05 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/blank-team-scopes` |
| Upstream issue / PR | none yet; asked Brad directly on 2026-10-05 |

**Blocked on:** Brad's answer to whether this is intentional (question below). The answer decides between the two fixes.

## Summary

An event saved without a team doesn't appear for any non-admin: not on the Events list, not on the calendar, and not in anything built on `policy_scope(Event)`. The scope looks like it means to include team-less events, but the clause it uses matches nothing.

We found this in production on 2026-10-05. Events created by a script with no team were missing for a manager, and so were their check-ins in a report Page that reads `pundit_policy_scope(Event)` for managers. Admins saw everything, so the two views of the report disagreed. Data workaround applied: every team-less event was given a team. No code changes yet.

## Where things are today (upstream `32e8023`)

- **The clause:** `app/policies/event_policy.rb`, line 7:
  `scope.where(team_id: person.all_teams.map(&:id)).or(scope.where(team_id: ""))`.
  `events.team_id` is a uuid (`db/schema.rb`, `create_table "events"`). Rails casts `""` to nil for uuid columns, but `where` keeps it as a bound value, so the SQL is `"events"."team_id" = NULL`. That is never true, so team-less events never match. Verified with `Event.where(team_id: "").to_sql` on a dev database.
- **Announcements already do it right:** `app/policies/announcement_policy.rb`, line 7 adds `.or(scope.where(team_id: nil))`, and `app/models/infodump.rb`, line 39 queries `where(team_id: nil)` too. That suggests "no team = everyone" was the intended meaning.
- **Same pattern elsewhere:**
  - `app/policies/page_policy.rb`, line 8: team-less Pages are hidden unless their viewer is `public` or `user`.
  - `app/policies/shortcut_policy.rb`, line 7: harmless, since `shortcuts.team_id` is `null: false`.
  - `app/policies/checkin_field_response_policy.rb`, line 7: `checkin_field_responses` has no `team_id` column, so this scope would raise if called. Nothing calls `policy_scope(CheckinFieldResponse)` today.
  - `lib/generators/policy/templates/policy.rb.tt`, line 8: the policy generator template repeats the pattern, so every new policy inherits it.
- **The form points the other way:** `app/views/events/_form.html.erb`, line 24 uses `include_blank: admin?` on Team. Only admins can leave Team blank, so "no team" may be meant as admin-only. This is why we asked before fixing it.
- **Where it's used:** `EventsController#index` (`policy_scope(Event)`, line 6) and `CalendarController` (line 13), plus any dynamic Page that calls `pundit_policy_scope(Event)`.

## Question sent to Brad (2026-10-05)

> In `EventPolicy::Scope`, non-admins get `...or(scope.where(team_id: ""))`. Since `team_id` is a uuid, that becomes `team_id = NULL` in SQL, which never matches, so team-less events are admin-only. Is that intended? If they're meant to be visible to everyone (as `AnnouncementPolicy` does with `.or(scope.where(team_id: nil))`), I'm happy to send a small PR covering this and the same pattern in the Shortcut, CheckinFieldResponse and Page policies. If admin-only is deliberate, could the event form say so, so a blank Team doesn't hide an event by surprise?

## Proposed fix

**If team-less means "everyone" (likely):**

1. Replace `.or(scope.where(team_id: ""))` with `.or(scope.where(team_id: nil))` in the Event and Page policies, and in the generator template.
2. Shortcut: drop the dead clause, or leave it alone (the column can't be null).
3. CheckinFieldResponse: scope through the check-in's event team (`joins(checkin: :event)`), or leave it for a separate change, since nothing calls it.
4. Clean up `AnnouncementPolicy` and `infodump.rb` to use only `nil`, if upstream wants consistency.

**If admin-only is intended:**

1. Make the intent explicit: remove the `team_id: ""` clause so the code says what it does.
2. Add a hint to the event form's Team field for admins, along the lines of "Leave blank to make this event visible to admins only."

## Hooks

No hook changes. Visibility scopes don't create, update or destroy records, so no `CanBeHooked` callbacks or catalog entries are affected.

## Tests

- `EventPolicy::Scope`: a non-admin member sees events on their teams and team-less events, and doesn't see events on other teams. (Admin-only variant: a non-admin doesn't see team-less events, and an admin does.)
- `PagePolicy::Scope`: a team-less page whose viewer isn't `public` or `user` follows the same rule.
- `EventsControllerTest#index` as a non-admin includes a team-less fixture event.
- No current test covers team-less records (`git grep 'team_id: nil' test` is empty), so add a fixture event with `team: nil`.

## Fork strategy notes

- Generic upstream bug with a one-line core fix. Send it as a direct PR after Brad answers. Don't carry it unless he declines.
- No migration, no flag.
- Until then, every event needs a team. That includes events created by scripts: always set `team_id`.

## Draft upstream issue

> **Records with no team are hidden by `team_id: ""` scopes**
>
> Several policy scopes include team-less records with `.or(scope.where(team_id: ""))`. On uuid columns, Rails casts `""` to nil and generates `team_id = NULL`, which never matches, so (for example) events with no team are visible only to admins. `AnnouncementPolicy` handles this with an extra `.or(scope.where(team_id: nil))`. Affected: `EventPolicy`, `PagePolicy`, the policy generator template, and (latently) `CheckinFieldResponsePolicy`, whose model has no `team_id`. If team-less is meant to mean "everyone," I can send a PR switching these to `team_id: nil` with tests.
