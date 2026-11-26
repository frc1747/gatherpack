# BL-087: Malformed or racing requests give a server error instead of a refusal

| | |
|---|---|
| Kind | upstream bug (two cases) + fork bug (`feature/forms`, two cases) |
| Priority | low |
| Status | not started |
| Added | 2026-11-25 |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | `feature/bad-input-422` (from `upstream/main`) for the upstream cases; the forms cases on `feature/forms` |
| Upstream issue / PR | none yet |

## Summary

An authenticated ZAP scan of Ditto (hbr.56, signed in as a plain student) sent garbage and concurrent requests to every form the student could reach. Permission checks held everywhere, but 163 requests ended in a 500 error page where a 422 or a polite message belongs. No data was damaged: the database constraints stopped every bad write. The cost is noisy error logs and an error page for the rare real user who double-submits.

| Request | Cause | 500s in the scan |
|---|---|---|
| `POST /calendar_notes` with a malformed id field | `NeatIds.find` raises `NeatIds::Error` on an unknown prefix, before `authorize` runs | 115 |
| `PATCH /forms/:id/responses/:person` twice at once | two drafts get the same `number`; the unique index raises `RecordNotUnique` | 33 |
| `PATCH /people/:id` with a tampered avatar `signed_id` | `ActiveSupport::MessageVerifier::InvalidSignature` | 12 |
| `PATCH /forms/:id/responses/:person` with a NUL byte in an answer | `PG::UntranslatableCharacter` | 3 |

## Where things are (upstream `3d5ce8f96`)

- `app/models/application_record.rb:41-43`: `assign_global_id` calls `NeatIds.find(gid)` on any non-blank value; `NeatIds.find` raises on an unknown prefix instead of returning nil. Same in `assign_global_ids` (`:51-52`).
- `app/controllers/calendar_notes_controller.rb:26`: `authorize CalendarNote.new(calendar_note_params)`. The raise happens while building the record, so an unauthorized user gets a 500 rather than the refusal (542 well-formed attempts in the same scan were refused correctly).
- `app/controllers/people_controller.rb:55-56`: `@person.update(person_params)` with `:avatar` (`:110`) accepts a signed blob id; a bad signature raises.
- `app/controllers/application_controller.rb:28`: only `Pundit::NotAuthorizedError` is rescued.
- `feature/forms`: `app/models/form_response.rb:37` `start_submission!` computes `maximum(:number) + 1` without a lock; `app/controllers/form_responses_controller.rb:28,32`.

## Proposed fix

Upstream branch:
- `assign_global_id` / `assign_global_ids`: rescue `NeatIds::Error` and treat the id as not found (add an error to the record so the save fails with 422).
- `ApplicationController`: `rescue_from ActiveSupport::MessageVerifier::InvalidSignature` and `ActionController::BadRequest`-style input errors with a 422 "That request couldn't be read." (redirect back with an alert for HTML).

`feature/forms`:
- `start_submission!`: take `with_lock` on the response before reading `maximum(:number)`, and retry once on `RecordNotUnique` by returning the now-open submission.
- Strip `\u0000` from answer strings before saving (Postgres text can't hold it).

## Tests

- Calendar note create with `team_nid: "bogus_x"` as a non-admin: refused (403/redirect), no 500.
- Person update with `avatar: "garbage--signed-id"`: 422 with a message, person unchanged.
- Two concurrent `start_submission!` calls on one response: one draft, no exception.
- Form answer containing `"a\u0000b"` saves as `"ab"`.

## Fork strategy notes

Found by `~/dev/gatherpack-import/jobs/zap/` (authenticated scan, student role). Upstream cases: confirm with Corey before any issue or PR. The forms cases are fork-only and go on `feature/forms`.
