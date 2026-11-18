# BL-053: Events where members shouldn't check themselves in must be locked one at a time

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | shipped hbr.50 (`feature/event-type-starts-locked`) |
| Added | 2026-11-17 |
| Commit checked | `upstream/main` @ `eeaa691aa`; `hbr/integration` @ `14fc6e1d8` |
| Planned branch | `feature/event-type-starts-locked` |
| Upstream issue / PR | none |

## Summary

Every new event starts unlocked, and anyone who can see an unlocked event can check themselves in. For events where attendance earns credit (outreach events counting toward a commitment, for example), a manager has to remember to tick **Locked** on each event, or members can mark themselves present and get credit. Nothing on the event page shows whether an event is locked, so a missed one goes unnoticed.

## Evidence

- `app/policies/checkin_policy.rb`: upstream lines 8-10 allow `create?` when the event isn't locked. The fork's version (`feature/security-series`, commit `1e9d79fee`) narrows this to "only themselves", but an unlocked event still accepts a member's own check-in.
- `locked` is a plain nullable boolean on `events` with no default (`db/schema.rb`, `events` table), set only by the tick box at `app/views/events/_form.html.erb:11` (upstream line numbering).
- Every check-in path goes through the policy: `CheckinsController#create` and the MCP `record_checkin` tool (`app/models/mcp/tools/record_checkin.rb:37-38`). Locking an event closes all of them, so locking each event by hand works as a stopgap.
- `event_types` has only `name` (`db/schema.rb`), so there's nowhere to say "events of this type are manager check-in only".
- The MCP `get_event` and `list_events` results leave out `locked`. Only `update_event` returns it.

## Fix

Behind a flag, default off (`feature_event_type_starts_locked`):

- **Event type row flag** (AGENT.md rule 13: behavior is a flag on the row): add the reversible migration `event_types.starts_locked boolean, default false, null false`. Add a tick box on the event type form, labelled "New events start locked (only admins and the team's managers can check people in)".
- **New events take it:** `Event` sets `locked = true` on create when the type starts locked, even if the form left Locked unticked (the form always sends the box, so "not given" can't be told apart). This covers the new-event form, the MCP `create_event` tool, and any copy or import that creates events. Changing an event's type later leaves its lock alone. A manager can still untick it on a single event.
- **Show it:** add a "Locked" badge on the event page beside the type, with the hover text "Only admins and the team's managers can check people in". Add `locked` to the MCP `get_event` and `list_events` results.
- **Clearer field label:** on the event form, label **Locked** as "Only managers can check people in".

Defaults: off for every existing event type. Existing events are left as they are.

## Tests

- Model: a new event of a `starts_locked` type is locked. One created with `locked: false` is locked too; unlocking it afterwards sticks. Changing the type of an existing event doesn't change its lock.
- Policy: a member can't check themselves in to an event created from a `starts_locked` type, and the team's manager can check them in.
- MCP: `create_event` with a `starts_locked` type returns a locked event, and `get_event` includes `locked`.
- Flag off: the type field is hidden and new events start unlocked as before.

## Fork notes

- New migration on `event_types`. Editing `app/models/event.rb`, `app/views/event_types/_form.html.erb`, `app/views/events/_form.html.erb` and `app/views/events/show.html.erb` touches upstream files: record them in `FORK.md` "Upstream files touched". Prefer an `Event` concern for the `before_create` callback.
- HBR rollout: turn on `starts_locked` for the Outreach event type. Until then, lock each outreach event by hand.
- Sample data: one Northwind event type with `starts_locked` on.
