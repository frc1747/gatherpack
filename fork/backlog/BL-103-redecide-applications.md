# BL-103: A membership application can be approved after it was denied, or approved twice

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56); same in upstream `3d5ce8f96` |
| Planned branch | `feature/application-decisions` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

Approving or denying an application doesn't check that it's still pending. A manager can approve an application that was already denied, or approve one twice (creating the membership again or raising an error).

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/controllers/membership_applications_controller.rb:37-47`: calls `approve!` / `deny!` directly.
- `app/models/membership_application.rb:22-30`: `approve!` creates the membership and updates the status.

## Proposed fix

`approve!` and `deny!` act only on pending applications; otherwise the controller redirects with "This application was already decided."

## Tests

- Approve a denied application: refused, no membership.
- Approve twice: one membership, the second says it was already decided.

## Fork strategy notes

Upstream file edit; confirm with Corey before any issue or PR.
