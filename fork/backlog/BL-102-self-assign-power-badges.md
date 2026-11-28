# BL-102: Self-assignable badges can grant powers

| | |
|---|---|
| Kind | upstream gap (configuration) |
| Priority | low |
| Status | not started (lead: check Ditto's badges first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | `feature/badge-grant-guard` |
| Upstream issue / PR | none yet |

## Summary

Badges whose permission is "has account", "added by admin or self", "added by manager or self" or "added by current member" can be taken by anyone for themselves. That's fine for interest badges, but if such a badge is also the forms creator badge, a sign-up organizer badge, an orders grant or a form grant, anyone can give themselves that power.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/policies/badge_assignment_policy.rb:60-74`.
- Grant settings: `forms_creator_badge`, the orders grant rows, checklist organizers, form badge grants.

## Proposed fix

When a badge is chosen as a grant (in any of those settings), require that its permission isn't self-assignable, or warn on the setting's page and on the badge's page ("Anyone can take this badge, so anyone gets <power>").

## Tests

- Choosing a self-assignable badge as the forms creator badge shows the warning (or is refused).
- Ditto: list self-assignable badges and cross-check every grant setting.

## Fork strategy notes

Spans upstream badges and fork grant settings; the guard lives with each fork grant.
