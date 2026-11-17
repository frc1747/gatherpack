# BL-028: Members can enter and change their own time clock punches by hand

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-04 |
| Fork code checked | `hbr/integration` and the latest HBR release, 2026-11-04 |
| Planned branch | none yet |
| Upstream issue / PR | none |

## Summary

Punches should come from two places: a member scanning their badge at the kiosk, or a manager or admin entering them by hand. Members shouldn't report their own time.

The Time Clock page doesn't enforce this. In some periods, a member who manages no team can edit their own open punch, add an end time, and save. A student can clock in at a meeting, leave, and later end the punch at whatever time they like, from home. They can also add a finished punch for a meeting they didn't attend.

The wrong hours are easy to miss. On the reports a closed punch looks the same however it was closed, and the flagged page stops listing it as still clocked in. Only the audit log shows who did it.

It depends on the punch's period:

| The member's own punch | Can they change it by hand? |
|---|---|
| In no period | Yes |
| In an *added by user* period | Yes |
| In an *added by team member* period | Yes |
| In an *added by manager* period | No |
| In an *added by admin* period | No |

HBR's attendance and eligibility reports count only punches in a named period, so a punch in no period doesn't reach them. Check which permission production's periods use, and whether members have already entered punches by hand. If all periods are *added by admin*, this can't change HBR's reported hours today, but one period set differently would open it up.

## Evidence

A test signed in as a member who manages no team and sent `PATCH /time_clock_punches/:id` with an end time for their own open punch. It gave the results in the table on merges of both `hbr/integration` and the latest release, 2026-11-04.

- `app/policies/time_clock_punch_policy.rb`, `update?`: true for the person's own punch in no period, and for periods with *added by user* or *added by team member* permission. `destroy?` is the same rule.
- `app/controllers/time_clock_punches_controller.rb`, `time_clock_punch_params`: `end_time`, `start_time` and `person_id` are permitted for anyone who passes `update?`.
- `app/models/time_clock_punch.rb`, `permission_check`: passes for these same permissions.
- Upstream's policy and controller have the same code, but this hasn't been run on plain upstream. Prove it there before reporting it. Upstream may see self-reporting as what *added by user* is for.

Other changes the same rules allow, all run through the MCP tools, which followed these rules until MCP was limited, and read from the code for the page:

- Deleting an open punch and adding a finished one.
- Moving an open punch to a teammate, in an *added by team member* period.
- Moving an open punch's start into the future. It drops out of the MCP clocked-in list, and a clock-out can't close it because the end would come before the start.

## Proposed fix

Add a setting, off by default, and turn it on for HBR. While it's on:

- Only admins and managers can create, edit or delete a punch by hand, within what they can already do today.
- Members can still see their own punches.
- The Time Clock page hides New, Edit and Delete from members.

Put the rule in `TimeClockPunchPolicy` and check it in `TimeClockPunchesController`. **Keep it out of the `TimeClockPunch` model.** The kiosk saves through the model, so a rule there would stop members clocking in and out by badge.

*Added by user* and *added by team member* would no longer let members enter punches by hand. Check whether those settings still affect who can clock in at the kiosk, and describe them accordingly.

The latest release's punch policy differs from `hbr/integration`'s, so confirm the rule works on both.

## Tests

With the setting on:

- A member can't create, edit or delete their own punch by hand, in no period, or in *added by user* or *added by team member* periods. Nothing changes.
- The same member can still clock in and out by badge at the kiosk, in every period they could before.
- A manager and an admin can still create, edit and delete what they can today.
- A manager's mass clock-out at the kiosk still works.
- The page hides New, Edit and Delete from a member, and shows them to a manager.

With the setting off, everything behaves as it does today.

## Fork strategy notes

- MCP already has this rule: `record_punch`, `update_punch`, `remove_punch` and `clock_out` refuse anyone but an admin or a manager. That was an owner decision, stricter than the page until this is fixed.
- Once fixed in the app, `Mcp::PunchRecords#may_enter_punches?` can use the same policy rule.
- No data is exposed, so this isn't marked `(security)`.
