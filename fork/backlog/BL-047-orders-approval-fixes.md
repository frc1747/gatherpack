# BL-047: Order request approval: three bugs and three gaps against the spec

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | medium |
| Status | shipped hbr.42 |
| Added | 2026-11-15 |
| Commit checked | `feature/orders` @ `b7518138` (in `v0.0.0-hbr.41`) |
| Planned branch | `feature/orders` |
| Upstream issue / PR | none |

## Summary

Found while writing the "Approve order requests" help guide on hbr.41. The guide leaves these out until they're fixed.

## Bugs

1. **Fix an item: field ids repeat.** Each item's edit form on a request uses the same field ids. With two or more items, every label points at the first item's box, so clicking a label focuses the wrong field and screen readers misread the form. Give each form's ids a per-line prefix (`namespace:` on the form builder, or the line's id).
2. **A declined request's items still say "Waiting for approval".** `app/helpers/orders_helper.rb:17` maps the line status `pending` to "Waiting for approval" whatever the request's state. When the request is declined (or withdrawn), show the request's outcome for its items instead.
3. **Re-approval shows "This request $0.00".** `app/views/orders/decisions/_funding.html.erb:43` totals only the items not yet approved. On a re-approval it should show the new total (or the increase, labelled as such) so the approver sees what they're agreeing to.

## Gaps against the orders spec

4. **"Needed by soon" is a fixed 3 days** (`Orders::Reminders::NEEDED_SOON_DAYS`, `app/models/orders/approval_flags.rb:14`), not a store lead time. Stores have no lead time field. Either add one or change the spec to the fixed window.
5. **A re-approval has no "Ask for changes"**, and the requester isn't told the decision. Add both, or record in the spec why not.
6. **Declining a re-approval requires a comment**, but the box says "Comment (optional)" (`app/views/orders/requests/_decision.html.erb:111`). Use the same placeholder as a first approval ("needed to ask for changes or decline").

## Tests

Controller or system tests for each bug: label `for` attributes unique across two items; a declined request's items show the decline; the re-approval funding line shows a non-zero total; the placeholder text on a re-approval.
