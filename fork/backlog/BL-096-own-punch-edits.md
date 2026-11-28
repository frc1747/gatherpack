# BL-096: Members can lengthen or back-date their own time clock punches

| | |
|---|---|
| Kind | upstream bug (by design?) |
| Priority | medium |
| Status | not started (lead: check HBR's setting first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | `feature/own-punch-limits` (from `upstream/main`), or a setting |
| Upstream issue / PR | none yet |

## Summary

A member may edit any of their own punches that aren't in a period, and create period-less punches for any past date, with any length; the model only checks that the end is after the start. Hours feed eligibility reports. The "only admins and managers enter or change punches by hand" setting turns this off; with it off, nothing limits it.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/policies/time_clock_punch_policy.rb:31-51`: `create?` allows `person == record.person`; `update?` allows the person on a period-less punch.
- `may_enter_punches?` reads `time_clock_hand_punches_managers_only`.
- `app/models/time_clock_punch.rb` `valid_times`: end after start only.

## Proposed fix

Check HBR's setting (if on, HBR is covered). For the default: when the setting is off, a member's own edits can't move a punch's start or end by more than a set amount (default 15 minutes) or create a punch more than a day old; longer changes need a manager. Make the limits settings on the time clock setup page.

## Tests

- Policy spec: member edits own period-less punch +11 h: refused with the setting off; within 15 minutes: allowed.
- Member creates a punch dated last month: refused.
- Managers and admins unaffected; the setting on refuses all member hand edits as today.

## Fork strategy notes

Upstream file edit; confirm with Corey before any issue or PR.
