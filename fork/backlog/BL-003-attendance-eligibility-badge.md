# BL-003: Keep a travel-eligibility badge in sync with attendance

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | blocked |
| Added | 2026-10-03 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/attendance-eligibility` |
| Upstream issue / PR | none (HBR policy; see "Fork strategy notes" for the parts that could go upstream) |

## Summary

HBR decides travel eligibility from attendance: the share of meeting hours a student was punched in for. Today that number lives only in the attendance report Page. We want it fully automated. When a student reaches the threshold, they get a "Travel Eligible" marker on their profile. When they drop below it, the marker comes off.

The first idea was a Hook on time clock punches. That doesn't work on its own (see "Why not a punch hook"). The design below recomputes on a schedule instead, and optionally also queues a recompute when someone punches out.

**Blocked on:** the eligibility threshold. `eligibility_percent` in the report is still `nil` while we wait for mentor feedback. The questions under "Decisions needed" also have to be answered before building.

## How attendance is calculated today

Source: the dynamic Page at `~/dev/gatherpack/pages/attendance-report.html.erb`. It isn't in the repo; its source is stored in the Page record and kept locally next to `team-roster.html.erb`.

- **Meetings** are events linked to the time clock period that have already ended (`end_time < Time.current`, line 50). Their merged intervals give the hours available.
- **Credit** is only the time a student's completed punches overlap a meeting (line 58 onward). Leaving early costs hours. Staying late or punching in on other days adds nothing (that time is shown as "extra").
- **Percentage** = credited hours ÷ available hours.
- **Who's counted:** regular (non-manager) members of the `report_teams` and their sub-teams.
- The threshold is `eligibility_percent` (line 8). People below it are highlighted.

The report deliberately doesn't use `TimeClockPeriod#available_hours`. That method has the date-bounds bug in [BL-002](BL-002-period-hours-date-bounds.md) and counts all punched time, not just meeting overlap.

## Why not a punch hook

Hooks can fire on punches. `TimeClockPunch` includes `CanBeHooked`, which upstream added in `ab072c0`. Punch-in is a `create` and punch-out is an `update` that sets `end_time` (`app/controllers/time_kiosk_controller.rb:35`, `:47`, `:60`, `:72`). But a punch hook can't keep the marker correct:

1. **Absences don't create records.** A student who skips a meeting writes no punch, so no hook fires for them. Their percentage falls while their marker stays. The students who should lose eligibility are the ones the hook never sees.
2. **Time passing changes the denominator.** A meeting only counts once it ends, and nothing is saved when it ends. Every completed meeting lowers the percentage of everyone who wasn't there.
3. **Meeting edits change everyone's numbers.** Adding, moving, or linking an event changes the available hours for the whole roster.
4. **A failing hook breaks the punch.** `CanBeHooked` (`app/models/concerns/can_be_hooked.rb:5-7`) runs hooks in `after_create`/`after_update`, inside the save transaction. `Hook#run` (`app/models/hook.rb:25-26`) just `eval`s the code and doesn't rescue errors. If the hook raises, the punch is rolled back and the kiosk returns a 500.
5. **The event can't be selected.** `time_clock_punches` isn't in `Hook.catalog` (`app/models/hook.rb:7`), and the hook form only offers catalog events (`app/views/hooks/_form.html.erb:9`). The hook would have to be created from the console.

## Proposed design

1. **A shared calculator in a new file**, for example `app/services/hbr/attendance_calculator.rb` (namespaced as `Hbr::`, because this is carried HBR policy). It takes a period and a set of people and returns the same rows the report shows: meetings attended, credited hours, missed hours, extra hours, and the percentage. Move the report's logic into it unchanged, and make the report Page call it, so the Page and the marker can never disagree.
2. **A recompute job**, for example `Hbr::AttendanceEligibilityJob`. It runs the calculator for the whole roster and the current period, then adds or removes the marker for each person. Make it idempotent so repeated runs change nothing.
3. **Scheduled in `config/recurring.yml`**, next to the existing `generate_notifications_job` (line 10). Solid Queue is already the production adapter. Run it nightly, or shortly after the Thursday meeting ends. This is the only edit to an upstream file.
4. **Optional faster updates:** a Hook on `time_clock_punches - update` that only calls `Hbr::AttendanceEligibilityJob.perform_later` when `end_time` was just set. Queuing the job instead of calculating keeps a calculation bug from blocking the kiosk. Wrap the hook in `rescue` anyway. This needs `time_clock_punches` in the catalog, or the hook has to be created from the console (see "Related").
5. **The marker is a badge**, for example "Travel Eligible", with permission `added_by_admin`. Badges already exist upstream, appear on profiles, can be filtered, and fire hooks. A boolean person field would tie this to `feature/person-fields`, which is still wip. A badge also works with that branch's badge grants, for example to show travel-only fields to eligible students.
6. **A feature flag in `Settings`**, off by default. Also store the threshold, the report teams, and the badge in Settings instead of hard-coding them.

## Decisions needed

- **Threshold:** the percentage, still pending mentor feedback.
- **Early-season swings:** after two meetings, one absence means 50%. Require a minimum number of meetings before evaluating? Or decide eligibility as of a cutoff date before each trip instead of recalculating continuously?
- **Mentor overrides:** a mentor who grants eligibility by hand would have it removed on the next run. Use a separate override badge that the job respects, or an exemption list.
- **Scope:** only the current period, or the whole season when it spans more than one period?
- **Notifications:** should students or mentors be told when the badge is added or removed? The badge assignment's own hooks (`badge_assignments - create` / `- destroy`) could handle that.

## Tests

- Calculator: matches the report for overlapping punches, early departure, staying late, punches on non-meeting days, meetings that haven't ended yet, and a period with no meetings (percentage `nil`, no change to the badge).
- Job: adds the badge at or above the threshold, removes it below, leaves overrides alone, and changes nothing on a second run.
- Job: only touches people in the report teams. Managers and people outside the teams are ignored.
- Hook (if built): punch-in doesn't queue the job, punch-out does, and an exception in the hook doesn't roll back the punch.

## Fork strategy notes

- HBR-specific policy, so this is a **carried** feature: `Hbr::` namespace, a flag, and only new files except for the one `config/recurring.yml` entry. Record that file in `FORK.md`.
- It doesn't depend on `feature/person-fields` if the marker is a badge.
- Before trusting the numbers, check whether backfilled punches need the [BL-002](BL-002-period-hours-date-bounds.md) boundary handling. Our periods end Jun 30 and Dec 31.

## Related, not part of this item (not yet backlogged)

Both are upstream bugs we found while looking into this. They would be separate small branches.

- **`Hook.catalog` drift.** 31 models include `CanBeHooked`, but only 17 table names are in the catalog. The 14 missing ones can't be chosen in the hook form even though their callbacks fire: `time_clock_punches`, `time_clock_periods`, `mailboxes`, `mailbox_messages`, `mailbox_assignments`, `gateways`, `budgets`, `budget_periods`, `questions`, `replies`, `membership_applications`, `checkin_field_responses`, `ledger_entry_links`, `ledger_entry_linkings`. The catalog was last changed in `c3f896c`/`5c248c7` (2025-08-31), when only the ledger tables were added. A fix that can't drift would build the list from the models that include `CanBeHooked`. `feature/person-fields` already edits this method, so expect a conflict.
- **Scanning a Hook token at the kiosk crashes.** Upstream issue #150 said that scanning a Hook's token runs the hook. The first kiosk (`c1c35be`) did that. The rewrite in `90855a8` (2025-08-24) replaced the call with `@time_kiosk.tool = "found_hook"` (`time_kiosk_controller.rb:21-23`), but there's no `_found_hook` partial. `_kiosk.html.erb` does `render @time_kiosk.tool`, so this should raise `MissingTemplate` (found by reading the code, not run). Ask Brad what he intends before fixing it.
