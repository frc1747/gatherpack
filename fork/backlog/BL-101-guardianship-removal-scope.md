# BL-101: A manager of only the guardian can remove a guardianship for a child on another team

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | `feature/guardianship-scope` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

Removing a minor guardianship is allowed to anyone who manages either side. A mentor who manages an adult on their team can therefore cut that adult off from their child on a team the mentor doesn't manage, which removes the guardian's access to the child's records.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/policies/relationship_policy.rb` `destroy?` (and `reverse?`): `person.can_manage(record.parent) || person.can_manage(record.child)` for minor types.

## Proposed fix

For guardianship (minor) types, require managing the child (or admin). Managing only the guardian isn't enough.

## Tests

- Policy spec: manager of the guardian only: `destroy?` false; manager of the child: true; admin: true.
- Ditto: `DELETE /people/:guardian/relationships/:id` as such a mentor: refused.

## Fork strategy notes

Upstream file edit; confirm with Corey before any issue or PR.
