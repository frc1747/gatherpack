# BL-043: Check-in fields and event types with stored answers can never be deleted

| | |
|---|---|
| Kind | upstream bug (check-in fields); fork follow-up to BL-031/BL-032 (event types) |
| Priority | low |
| Status | started (`feature/event-type-checkin-fields`, see `FORK.md`) |
| Added | 2026-11-11 |
| Commit checked | `hbr/integration` @ `f19a201d` (`v0.0.0-hbr.38`) |
| Planned branch | `feature/event-type-checkin-fields` (BL-031's branch) |
| Upstream issue / PR | none |

## Summary

Two deletes are refused with no way out:

- **Check-in field.** Once any check-in has a response row for the field, even a blank one (every check-in gets one when the field is created), the delete is refused. On hbr.38 the admin sees *This can't be deleted while other records still use it.* (BL-019's handler, confirmed with a throwaway test on 2026-11-11; the help site's "error page" note was from an unclicked probe). On plain upstream it's an error page. Fields can't be archived either, so the only workaround is to hide the field by permission.
- **Event type.** BL-031 refuses the delete when the type's check-in fields still hold answers, which after BL-032 happens whenever an event moved to another type kept its old answers. Nothing on screen clears those kept answers, so the type stays forever. BL-032's decision was that kept answers go *when the old type is deleted, after asking*; BL-031 refuses instead.

Found by the help site's admin guides (tasks 97 and 98, hbr.38).

## Where things are (`f19a201d`)

- `app/controllers/checkin_fields_controller.rb`, `destroy`: `@checkin_field.destroy!`.
- `app/models/checkin_field.rb:6`: `has_many :checkin_field_responses`, no `dependent:`; `db/schema.rb`: `add_foreign_key "checkin_field_responses", "checkin_fields"`.
- `app/models/event_type.rb` on `feature/event-type-checkin-fields`: the refusal *Cannot delete an event type whose check-in fields have responses*.

## Fix (2026-11-11)

- `CheckinField` destroys its responses in a `before_destroy` (the same as `dependent: :destroy`, placed away from the lines `feature/person-fields` adds so the rebuild merges cleanly): each removal goes through the audit log and fires `checkin_field_responses` destroy hooks (the model includes `CanBeHooked`).
- `EventType` drops BL-031's refusal; its `dependent: :destroy` on check-in fields now removes kept answers too.
- The Delete confirmation on a check-in field and on an event type says "Are you sure? This also deletes N check-in answers." when any answers are filled in (`CheckinAnswersHelper`, `CheckinField#answer_count`, `EventType#checkin_answer_count`); blank responses aren't counted.

## Tests

`test/models/checkin_field_test.rb` (new), `test/models/event_type_test.rb`, `test/controllers/checkin_fields_controller_test.rb`, `test/controllers/event_types_controller_test.rb`: blank and filled responses go with the field and are audited; a type with kept answers deletes with them; both confirmations show the count.

## Fork strategy notes

Check-in field half is an upstream bug: prove on plain `upstream/main` (with `feature/test-hosts`) before reporting. The event-type half only exists because of BL-032's kept answers. Confirm with Corey before any issue or PR. When fixed, the help site's `admin/event-types` guide drops "Keep the type" and the check-in field troubleshooting entry.
