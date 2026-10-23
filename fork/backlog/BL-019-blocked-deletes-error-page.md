# BL-019: A delete the database refuses shows an error page

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | waiting |
| Added | 2026-10-11 |
| Upstream base checked | `86ab397` |
| Planned branch | `feature/blocked-delete-message` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

Most controllers delete with `destroy!` and nothing rescues the failure. When a record can't be deleted (a `dependent: :restrict_with_error` association, or a foreign key that still points at it), the admin gets an error page instead of a message saying why. BL-005 is one case (events with check-ins). It came up again with `feature/commitments`, which adds `Badge has_many :owing_commitments, dependent: :restrict_with_error` from its initializer: deleting that badge is correctly refused, but through an error page.

## Where things are (upstream `86ab397`)

- `app/controllers/badges_controller.rb:45-47` and `app/controllers/teams_controller.rb:76`: `destroy!` then redirect.
- 37 controllers call `destroy!` (`git grep -c "destroy!" upstream/main -- app/controllers`).
- `app/controllers/application_controller.rb:28`: only `Pundit::NotAuthorizedError` is rescued.

## Proposed fix

One `rescue_from ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey` in `ApplicationController` that redirects back with the record's errors (or "can't be deleted while other records use it"). That covers every controller without touching each. BL-005's fuller fix (saying what blocks it before the click) can build on it.

## Tests

- Deleting a badge with a restricting association redirects with an alert, and the badge remains.
- Deleting an event with check-ins (BL-005) shows the alert instead of an error page.

## Fork strategy notes

Upstream bug; confirm with Corey before any issue or PR.
