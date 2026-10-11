# BL-017: Events with no known time: "Time TBA" and all-day events

| | |
|---|---|
| Kind | upstream feature |
| Priority | low |
| Status | waiting |
| Added | 2026-10-11 |
| Upstream base checked | `86ab397` |
| Planned branch | `feature/event-time-display` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

An Event must have a start time, so there's no way to say "this happens on Saturday, time to be announced" or "this is an all-day event". Today the workaround is a placeholder time, which shows as if it were real.

Came up while writing the sign-ups spec (`fork/specs/signups-spec.md`, rev. 5): some game-day events are scheduled before the kickoff time is announced. Decided 2026-10-11: for now, enter such events as 00:00–23:59 on the day, and keep TBA and all-day as this backlog item. The sign-ups spec has no TBA of its own; it relies on its notice when an event's time changes (§3.7).

## Evidence (upstream `86ab397`)

- `app/models/event.rb`: `validates :start_time, presence: true`; `end_time` is optional. No flag for an unknown or all-day time.
- `db/schema.rb`, `events`: `start_time` and `end_time` are plain `datetime` columns.
- `app/views/calendar/calendar.json.jbuilder:5`: events are always `json.allDay false`, while calendar notes (`:35`) and punches (`:53`) are all-day when they have no end time. A 00:00–23:59 event shows as a full-height block in week and day views.
- `Event#hours` (`event.rb`) counts `end_time − start_time`, so a 00:00–23:59 placeholder is about 24 hours. Upstream doesn't use `Event#hours` for punches or period totals, but check fork features (attendance tracking only looks at period-linked events) before relying on that.
- Times are shown in several places that would all need to know: `events/show`, `events/index`, `teams/show.html.erb:193` (calendar), `teams/show_public.html.erb:115`, `to_combobox_display`, and fork panels that print event times.

## Proposed fix

One small column pair on `events`, shown everywhere an event's time is:

- `all_day` (boolean): show the date only; the calendar renders it as an all-day event. Stored as the day's start and end.
- `time_tba` (boolean): show the date and "Time TBA"; the calendar renders it all-day with a "TBA" label. Saving a real time clears it.

Open questions for the branch:

- One enum (`time_kind`: `timed`, `all_day`, `tba`) or two booleans? An enum stops the meaningless "all day and TBA".
- Should clearing TBA fire a hook (`events - time set`) so features like sign-up notices can react without their own diffing?

## Hooks

Events already include `CanBeHooked`; the new columns ride along on `events - update`. A named event for "time set" is the open question above.

## Tests

- Model: TBA and all-day validate and keep `start_time` on the right day.
- Calendar JSON: all-day and TBA events have `allDay: true`.
- Event show and index show "Time TBA" / the date only.

## Fork strategy notes

- Edits upstream files (`event.rb`, a migration, the event views, the calendar JSON), so it's its own `feature/*` branch from `upstream/main`, written to go upstream unchanged. Record the files in `FORK.md` when the branch exists.
- Generic and small: a reasonable upstream proposal. Confirm with Corey before opening anything upstream.
