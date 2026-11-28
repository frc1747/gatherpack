# BL-095: A member can change or delete their own check-in after the event is locked

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | `feature/locked-checkins` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

Locking an event stops new check-ins, but `CheckinPolicy#update?` and `#destroy?` don't look at the lock: the person checked in can still delete their check-in or rewrite its notes and field answers afterwards, which undoes what the lock was for (attendance and hours credit).

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/policies/checkin_policy.rb`: `new?` checks `event.locked?`; `update?` (`record.person == person || admin || team manager`) and `destroy?` don't.
- `CheckinsController` adds no lock check; `app/models/checkin.rb` has none.

## Proposed fix

`update?` and `destroy?`: for the person themselves, also require `!record.event.locked?`. Admins and the event's managers keep editing locked events, as `new?` allows.

## Tests

- Policy spec: member with a check-in on a locked event: `update?` and `destroy?` false; unlocked: true; manager and admin: true either way.
- Request spec: `DELETE /events/:id/checkins/:id` as that member on a locked event: refused, check-in kept.

## Fork strategy notes

Upstream file edit (`checkin_policy.rb`): list it in `FORK.md`. Confirm with Corey before any issue or PR.
