# BL-043: Check-in fields and event types with stored answers can never be deleted

| | |
|---|---|
| Kind | upstream bug (check-in fields); fork follow-up to BL-031/BL-032 (event types) |
| Priority | low |
| Status | new |
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

## Fix

Ask, then delete the answers, as BL-032 decided:

- `CheckinField has_many :checkin_field_responses, dependent: :destroy` (destroy, not delete, so each removal is audited and fires hooks). Blank rows go silently.
- When the field or type has non-blank answers, the Delete confirmation says how many ("This removes 14 answers from 9 check-ins.") before the click. Count with one query in the show view.
- Event type delete drops the BL-031 refusal and relies on the field's `dependent: :destroy`.
- Linked check-in fields (person-fields) store no responses, so they're unaffected.

## Tests

- Deleting a field with blank responses succeeds and removes them.
- Deleting a field with answers succeeds after the confirmation, removes them and writes audit entries.
- Deleting an event type with no events whose fields hold kept answers succeeds and removes fields and answers.
- An event type with events is still refused by the policy.

## Fork strategy notes

Check-in field half is an upstream bug: prove on plain `upstream/main` (with `feature/test-hosts`) before reporting. The event-type half only exists because of BL-032's kept answers. Confirm with Corey before any issue or PR. When fixed, the help site's `admin/event-types` guide drops "Keep the type" and the check-in field troubleshooting entry.
