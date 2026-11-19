# BL-031: Deleting an event type that has check-in fields crashes

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | started (`feature/event-type-checkin-fields`, see `FORK.md`) |
| Added | 2026-11-04 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Branch | `feature/event-type-checkin-fields` (from `upstream/main`) |
| Upstream issue / PR | none |

## Summary

An event type with no events can be deleted (`EventTypePolicy#destroy?` only checks `record.events.empty?`). If the type has check-in fields, the database refuses the delete and the admin gets an error page. Found 2026-11-04 in review of BL-005.

## Where things are (upstream `3fa5700`)

- `app/models/event_type.rb:5`: `has_many :checkin_fields`, no `dependent:`.
- `db/schema.rb`: `add_foreign_key "checkin_fields", "event_types"`.
- `app/policies/event_type_policy.rb:2-4`: `destroy?` is `record.events.empty?`.
- `app/controllers/event_types_controller.rb:47`: `destroy!`, unrescued. With BL-019 (`feature/blocked-delete-message`) the admin gets "can't be deleted" instead of an error page, which still leaves no way to delete the type.

## Proposed fix

Decide what a type's check-in fields mean without the type: they only exist to ask questions at that type's events, so `has_many :checkin_fields, dependent: :destroy` is likely right (their responses belong to check-ins, which belong to events, and the type has none). Check whether `checkin_field_responses` reference `checkin_fields` with a foreign key; if a field could have responses while its type has no events, use `restrict_with_error` instead and say why in the message.

## Hooks

`checkin_fields` would fire its own destroy hooks if it includes `CanBeHooked`; check.

## Tests

- Deleting a type with check-in fields and no events succeeds and removes the fields (or refuses with a message, per the decision).
- A type with events is still refused by the policy.

## Fork strategy notes

Small upstream bug; one model line plus tests. Confirm with Corey before any issue or PR.
