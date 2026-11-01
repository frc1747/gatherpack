# BL-027: Kiosk "Clock Out" for one period silently does nothing for mentors

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-01 |
| Fork code checked | `v0.0.0-hbr.25` (`e8d61506`); upstream `3fa5700e` for comparison |
| Planned branch | none yet (a fix to the security series, see Fork strategy notes) |
| Upstream issue / PR | none (upstream doesn't have the bug) |

## Summary

At the kiosk, a manager scans their card and opens **Manager**. The **Time Management** window lists each period on the teams they manage, each with a **Clock Out** button, plus **All Periods** with its own **Clock Out** when there's more than one period. For a non-admin manager, the per-period **Clock Out** does nothing when the period is *added by admin*. The kiosk goes back to the welcome screen with no message, and everyone stays clocked in. **All Periods → Clock Out** works for the same manager on the same periods.

Both periods on the demo (an anonymized copy of production) are *added by admin*. If production is the same, the per-period button is dead for every mentor who isn't an admin. A mentor who uses it at the end of a meeting will think everyone is clocked out when nobody is. That's wrong hours, and a wrong headcount for anyone checking Who's Clocked In.

Found 2026-11-01 while writing the gphelp guide "Clock everyone out and check Who's Clocked In". That guide tells mentors to use **All Periods** until this is fixed. Update the guide (`gphelp/docs/mentors/mass-clock-out/index.md`) when the fix ships.

## Evidence (fork `v0.0.0-hbr.25`)

- `app/controllers/time_kiosk_controller.rb:77-79`: `punch_out_period` only clocks out if `Pundit.policy(user, period).edit?`. Otherwise it falls through to the welcome screen without a flash message.
- `app/policies/time_clock_period_policy.rb:23-24`: `create?` (and `update?`/`edit?`, which call it) is `user.admin? || (manages?(record.team) && !record.added_by_admin?)`. Commit `89f1ba1f` ("Limit managers' new periods, ledgers, budgets and payments to their teams", branch `sec/05-manages`, released in hbr.24) added the `!record.added_by_admin?` part. Its aim was to stop managers creating or editing admin-only periods. Reusing `edit?` for the kiosk extended that rule to *closing open punches*, which was not the intent.
- `app/controllers/time_kiosk_controller.rb:92+`: `punch_out_all` only needs the scanned manager to have a login. It closes every open punch in `signed_person_managed_periods` (`app/models/time_kiosk.rb:55-62`), including on *added by admin* periods. So the two buttons in the same window disagree about the same periods.
- `app/views/time_kiosk/_found_person.html.erb:25-48`: both buttons are shown for every managed period, so the dead button looks just like the working one. **All Periods** only appears when the manager has more than one period (`managed_periods.many?`), so a mentor managing a single *added by admin* period has no working button at all.
- Upstream (`3fa5700e`) `TimeClockPeriodPolicy#update?` is `admin || all_managed_teams.include?(record.team)`, with no `added_by_admin` check, so upstream doesn't have this bug.
- Tests: `test/controllers/time_kiosk_controller_test.rb:139` ("punch_out_period clocks out the period for a manager") uses a period that isn't *added by admin*, so it passes.

## Proposed fix

1. Give the kiosk its own rule for closing a period's open punches, separate from editing the period. For example, `TimeClockPeriodPolicy#punch_out?` would be `user.admin? || manages?(record.team)`, whatever the period's permission. Ending punches doesn't change the period itself.
2. Use that rule in both `punch_out_period` and `punch_out_all`, so the two buttons agree. `punch_out_all` should only close periods the rule allows.
3. When the kiosk refuses a clock-out, say so (flash a warning such as "You can't clock out this period."), instead of returning silently to the welcome screen.

Open question: should a manager of a *parent* team be able to clock out a sub-team's period? Check whether `manages?` covers the teams below one you manage, as `managed_periods` (`all_managed_teams`) does, and make the two match.

## Tests

- `punch_out_period` by a non-admin manager on an *added by admin* period of a team they manage: punches are closed.
- `punch_out_period` by a manager of a different team: nothing closed, warning shown.
- `punch_out_all` closes exactly the periods `punch_out?` allows.
- Keep the existing refusals in `time_kiosk_controller_sec_test.rb` (non-manager, bare `person_id`, manager with no login).

## Fork strategy notes

- This is a regression in the fork's security series, so the fix goes on top of that series (or into the next `sec/release-*`), not on a `feature/*` branch from `upstream/main`. Upstream is unaffected.
- No data exposure. The issue is an over-strict check, plus an inconsistently looser one in `punch_out_all`, so this isn't marked `(security)`.
