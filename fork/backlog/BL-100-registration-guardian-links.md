# BL-100: A registration manager can choose any guardian type and link anyone as a minor's guardian

| | |
|---|---|
| Kind | fork bug (security, `feature/intake`) |
| Priority | medium |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | fix on `feature/intake` |
| Upstream issue / PR | none yet |

## Summary

A registration's guardian relationship type is accepted from params without checking who may add that type, and the guardians step links any person (by email or id) as guardian of a minor applicant; enrolment then saves the relationship with `validate: false`, skipping the type's "added by" rule. A mentor running one registration could make someone a guardian (with access to the child's profile) using a type only admins should add.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/controllers/intake/registrations_controller.rb`: `registration_params` permits `guardian_relationship_type_id`.
- `app/models/intake/registration.rb:170`: only requires a guardianship type.
- `app/controllers/intake/guardians_controller.rb:15-29`: any person by email or id.
- `app/models/intake/enrollment.rb:150-153`: `relationship.save!(validate: false)`.

## Proposed fix

Offer and accept only guardian types the registration's manager may add (the same rule `RelationshipPolicy#create?` uses). Enrolment saves with validations on (the rule that needs skipping gets its own explicit exception). A guardian linked by a non-admin who isn't the applicant's family is marked pending until the applicant (or an admin) confirms.

## Tests

- A mentor sets an admin-only guardian type: refused.
- Enrolment with an invalid relationship fails visibly instead of saving.
- The normal flow (parent registers child) still works.

## Fork strategy notes

Fork-only (`feature/intake`).
