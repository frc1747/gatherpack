# BL-051: Site admins get every team's notices

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | shipped hbr.54 |
| Added | 2026-11-17 |
| Commit checked | `hbr/integration` @ `14fc6e1d8` (`v0.0.0-hbr.49`) |
| Planned branch | `feature/orders` and `feature/intake` (one small change each), setting on the earlier of the two |
| Upstream issue / PR | none |

## Summary

Being a site admin is a permission: an admin *can* act on anything. Several fork notices also treat it as a reason to *mail* the admin, so the admin account gets every team's approval requests, registration alerts and join counts, in addition to whatever its own team roles bring. On a site where the admin account is a working mentor account, that buries the notices meant for them.

## Where admins are added as recipients

1. **Order approvals.** `Orders::Recipients.approvers` (`app/models/orders/recipients.rb:10-13`) picks `candidates(step.reach)` and keeps those passing `Orders::Access#approver_on?`, which is `admin? || …` (`app/models/orders/access.rb:47`). An admin is an approver on every step of every team, so they get submitted, step approved, needs re-approval, needed soon and undecided notices (`app/services/order_notices.rb:16,24,107,116,125`).
2. **Order buying notices.** Same pattern through `buyer_on?` (`access.rb:60`, `recipients.rb:21`). A person can already turn these off (My Orders → Buying notices).
3. **Registration "turning people away".** `Intake::Notices` (`app/models/intake/notices.rb:72`) mails `Team#all_managers_and_admins` (`app/models/team.rb:139-142`), which adds every admin.
4. **Intake daily join digest.** `Intake::DigestJob` (`app/jobs/intake/digest_job.rb:15-17`) mails every manager the counts for `all_managed_teams`, which is `Team.all` for an admin (`app/models/person.rb:128-129`). An admin who manages one team gets every team's count.

Not admin-specific (unchanged): announcements, the Weekly Infodump, Summaries, sign-up, form and commitment notices, and inventory low-stock notices (`InventoryNotices.managers` already skips admin status).

## Fix

Add a site setting **"Admins get notices for every team"** (`notices_admins_everywhere`, Notifications section of Setup, default **on** = today's behavior). When off:

- Recipient lists are built from real roles only: team manager flags (and their descendants), approval-step reach, buyer and funding grants. Admin status still grants every *permission*; it just doesn't add mail.
- **Nobody left = admins.** If a notice would have no recipients without admins (no approver configured for a step, a team with no manager), it still goes to admins, so nothing goes unseen.
- Implement once: `Person#notice_teams` = managed teams computed without the admin shortcut, and `Orders::Access` gains a `for_notices` mode that skips the `admin?` short-circuit. `Team#all_managers_and_admins` callers in notices use `all_managers` plus the fallback. Policies keep using the admin shortcut.

HBR sets it **off** on Ditto, then prod.

## Workarounds today (no code)

- My Orders → **Buying notices** → Off stops the buyer digest and "to buy" notices.
- Clearing the admin account's **manager** flag on its team stops the intake join digest (admin still manages everything).
- Approval notices and registration alerts have no switch.

## Tests

- Orders: with the setting off, an admin who isn't in a step's reach gets no submitted/step notice; an admin who is in the reach still does; a step with no non-admin approver falls back to admins. Setting on: unchanged.
- Intake: digest for an admin who manages one team lists only that team; registration-busy alert skips admins unless the team has no manager.
- Permissions unchanged: admin can still approve any request and see every registration.

## Fork notes

Fork code only (orders, intake); no upstream files. Setting registered with `Settings.register` in the owning feature's initializer, catalogued in `FORK.md`.

## Built

- Orders: task 383 on `feature/orders`, commit `3ba541fb6`, then `1fb901fbf` (the orders summary follows the same rule).
- Intake: task 384 on `feature/intake`, commit `d8b91fb5e` (`Person#notice_teams`, the registration alert and the join digest).
- Both register the same setting, `notices_admins_everywhere`, default on. It must stay on until hbr ships with the orders summary fix (`1fb901fbf`); that fix is now on `feature/orders`, so the setting can be turned off once the release carrying it is running. The row stays `started` until a release ships it.
- Left for a later merge: `OwnRoles#all_managed_teams` could share `Person#notice_teams` once both branches are in one build.
