# BL-030: A refused delete still writes a "destroy" audit entry

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | started (`feature/refused-delete-audit`, see `FORK.md`) |
| Added | 2026-11-04 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Branch | `feature/refused-delete-audit` (from `upstream/main`) |
| Upstream issue / PR | none |

## Summary

When the database refuses to delete a record (a foreign key still points at it), PaperTrail has already written the record's "destroy" version, and that version stays. The audit log then says the record was deleted while it still exists, and every retry adds another entry.

The versions live in a separate database (`db/versions_schema.rb`, `VERSIONS_DATABASE_URL`), so rolling back the primary transaction doesn't remove them. Measured on an event with check-ins: one destroy row after one refused delete, on plain upstream and on `feature/blocked-delete-message` (BL-019) alike. BL-019 doesn't cause it, but makes refused deletes a normal, repeatable path instead of an error page.

Found 2026-11-04 in review of `feature/blocked-delete-message`.

## Where things are (upstream `3fa5700`)

- `app/models/event.rb:4` and most models: `has_paper_trail versions: { class_name: "AuditLog" }`, which records destroys with `on: [:destroy]` before the delete by default.
- `AuditLog` is in the versions database.

## Options to look at

- `has_paper_trail ... on: ...` with destroy recorded after the delete (PaperTrail's `paper_trail_on_destroy(:after)`), where the gem version supports it. Then a refused delete writes nothing. Check what the "after" mode records as the object.
- Or prevent the predictable refusals before PaperTrail runs (BL-005's `dependent:` choices), and accept the rare leftover.

## Hooks

None.

## Tests

- Refused delete of an event with check-ins (before BL-005 is fixed, or with a stubbed FK failure): no new `AuditLog` row.
- A successful delete still records one destroy version with the object's last state.

## Fork strategy notes

Generic, touches whichever models get the option (or one shared concern). Find out first whether upstream wants it at all. Confirm with Corey before any issue or PR.
