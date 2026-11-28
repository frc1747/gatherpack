# BL-087: Malformed or racing requests give a server error instead of a refusal

| | |
|---|---|
| Kind | upstream bug (three cases) + fork bug (`feature/forms`, two cases) |
| Priority | low |
| Status | not started |
| Added | 2026-11-25 (calendar case 2026-11-26; campaign cases 2026-11-28) |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | `feature/bad-input-422` (from `upstream/main`) for the upstream cases; the forms cases on `feature/forms` |
| Upstream issue / PR | none yet |

## Summary

An authenticated ZAP scan of Ditto (hbr.56, signed in as a plain student) sent garbage and concurrent requests to every form the student could reach. Permission checks held everywhere, but 163 requests ended in a 500 error page where a 422 or a polite message belongs. No data was damaged: the database constraints stopped every bad write. The cost is noisy error logs and an error page for the rare real user who double-submits.

| Request | Cause | 500s in the scan |
|---|---|---|
| `POST /calendar_notes` with a malformed id field | `NeatIds.find` raises `NeatIds::Error` on an unknown prefix, before `authorize` runs | 115 |
| `PATCH /forms/:id/responses/:person` twice at once | two drafts get the same `number`; the unique index raises `RecordNotUnique` | 33 |
| `POST /calendar/calendar.json` with a malformed `start_time`/`end_time` | `Date.parse` raises `Date::Error` (birthdays on), or Postgres rejects the timestamp while the view renders (`PG::InvalidDatetimeFormat`) | 50 in 15 minutes (2026-11-26 run) |
| `PATCH /people/:id` with a tampered avatar `signed_id` | `ActiveSupport::MessageVerifier::InvalidSignature` | 12 |
| `PATCH /forms/:id/responses/:person` with a NUL byte in an answer | `PG::UntranslatableCharacter` | 3 |

The full campaign (2026-11-27/28: student, parent, mentor, student2 and architect deep scans, then the signed-out scan) found more of the same kind. Counts are across all runs; the error lines are in each run's `ditto-errors.log`.

| Request | Cause (upstream `3d5ce8f96`) | 500s |
|---|---|---|
| Relationship add form with the type or person missing | `Relationship#reify` raises a bare `ArgumentError` (`app/models/relationship.rb:15`) | 1,200 |
| Any list with `q[top_level]=<value>` | the `top_level` ransack scope takes no argument (`app/models/team.rb:25`) | 616 |
| Most lists with a non-uuid `q[..._id_eq]` (events, badges, announcements, pages, time clock periods, tokens, teams, sign-up sheets) | Postgres rejects the value while the view renders (`PG::InvalidTextRepresentation`) | 1,113 |
| Lists with a huge number in an id filter (people) | `PG::NumericValueOutOfRange` | 20 |
| Time clock summary with junk `starts_at`/`ends_at` | `Time.zone.parse` returns nil or raises "argument out of range"; `.to_date` on nil (`app/controllers/time_clock_periods_controller.rb:36,41,45-46`); also `time_clock_punch.rb` compares with nil | 745 |
| Team or funding source with an unknown enum value | `ArgumentError: '...' is not a valid join_permission / kind` | 20 |
| A NUL byte in any search box or text field (search, time clock, check-ins, memberships, inventory, orders) | `ArgumentError: string contains null byte` | about 110 |
| Any record id with an unknown prefix | `NeatIds::Error` from `application_record.rb:43` (beyond calendar notes) | 318 |

## Where things are (upstream `3d5ce8f96`)

- `app/models/application_record.rb:41-43`: `assign_global_id` calls `NeatIds.find(gid)` on any non-blank value; `NeatIds.find` raises on an unknown prefix instead of returning nil. Same in `assign_global_ids` (`:51-52`).
- `app/controllers/calendar_notes_controller.rb:26`: `authorize CalendarNote.new(calendar_note_params)`. The raise happens while building the record, so an unauthorized user gets a 500 rather than the refusal (542 well-formed attempts in the same scan were refused correctly).
- `app/controllers/calendar_controller.rb:9-10`: `start_time`/`end_time` come straight from params; `:15` and `:37` bind them into timestamp comparisons and `:20-23` call `Date.parse` on them. The queries are parameterized (no injection); only the parse fails.
- `app/controllers/people_controller.rb:55-56`: `@person.update(person_params)` with `:avatar` (`:110`) accepts a signed blob id; a bad signature raises.
- `app/controllers/application_controller.rb:28`: only `Pundit::NotAuthorizedError` is rescued.
- `feature/forms`: `app/models/form_response.rb:37` `start_submission!` computes `maximum(:number) + 1` without a lock; `app/controllers/form_responses_controller.rb:28,32`.

## Proposed fix

Upstream branch:
- `assign_global_id` / `assign_global_ids`: rescue `NeatIds::Error` and treat the id as not found (add an error to the record so the save fails with 422).
- `ApplicationController`: `rescue_from ActiveSupport::MessageVerifier::InvalidSignature` and `ActionController::BadRequest`-style input errors with a 422 "That request couldn't be read." (redirect back with an alert for HTML).

- `CalendarController#calendar`: parse both params once with `Time.zone.iso8601` (rescue `ArgumentError`) and answer 400 with an empty JSON array when either is missing or malformed.

`feature/forms`:
- `start_submission!`: take `with_lock` on the response before reading `maximum(:number)`, and retry once on `RecordNotUnique` by returning the now-open submission.
- Strip `\u0000` from answer strings before saving (Postgres text can't hold it).

Campaign cases (same branch):
- `rescue_from ArgumentError`-style input errors is too broad; instead fix each source: `Relationship#reify` adds a validation error instead of raising; `top_level` accepts and ignores an argument (`->(_ = nil) { ... }`); time clock summary falls back to the period's dates when a param doesn't parse; enum setters validate (`validate: true` on the enum, Rails 7.1+).
- Id filters: one `ApplicationRecord.ransack` wrapper (or a `before_action` on lists) that drops `*_id_eq`/`*_id_in` values that aren't uuids or in-range integers.
- NUL bytes: strip `\u0000` from params in one `before_action` in `ApplicationController`.
- `NeatIds::Error`: the `assign_global_id` rescue above covers every model.

## Tests

- Calendar note create with `team_nid: "bogus_x"` as a non-admin: refused (403/redirect), no 500.
- `POST /calendar/calendar.json` with `start_time: "2026-11-01T00:00:00.000ZNULL"`, with and without `birthdays`: 400, no 500.
- Person update with `avatar: "garbage--signed-id"`: 422 with a message, person unchanged.
- Two concurrent `start_submission!` calls on one response: one draft, no exception.
- Form answer containing `"a\u0000b"` saves as `"ab"`.

- Campaign cases: `GET /relationships/new` with no type: form shows, no 500; `GET /teams?q[top_level]=1`: 200; `GET /events?q[team_id_eq]=bogus`: 200, empty list; time clock summary with `starts_at=junk`: 200 with the period's dates; team update with `join_permission: "x"`: 422; a search with `%00`: 200.

## Fork strategy notes

Found by `~/dev/gatherpack-import/jobs/zap/` (authenticated scan, student role). Upstream cases: confirm with Corey before any issue or PR. The forms cases are fork-only and go on `feature/forms`.
