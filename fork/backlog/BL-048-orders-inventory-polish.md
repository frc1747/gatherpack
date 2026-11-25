# BL-048: Orders and inventory: screen problems found while writing help guides

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | high (1 is blocking) |
| Status | shipped hbr.42 |
| Added | 2026-11-15 |
| Commit checked | `v0.0.0-hbr.41` |
| Planned branch | `feature/orders`, `feature/inventory`, `feature/my-gatherpack-activity` |
| Upstream issue / PR | none |

## Blocking

0. **New request: every autosave after the first is refused (422 InvalidAuthenticityToken)**, so members can't submit a new request. Per-form CSRF tokens (load_defaults 8.0): the form's token is for POST /orders/requests; `order_form_controller.js` switches the form to PATCH the draft but keeps that token, and the fetch sends no `X-CSRF-Token`. A draft opened from /edit works. Fixed on `feature/orders` (session token header + swap the form's token after the first save).

## Members inventory / orders menus

1. A member's More menu lists To buy and Reports, which they can't open; Turbo hover-prefetch then flashes "You are not allowed to do that" on the next page.
2. Phone item page: the Undo toast renders below History, off screen.
3. A history entry for order-received parts shows the raw order URL, which overflows on a phone.
4. No menu link to Machines.

## Manage inventory

5. Import Preview does nothing in a browser: Turbo rejects the non-redirect response ("Form responses must redirect to another location").
6. Changes page: the big-count highlight is invisible (the theme's row colour covers it).
7. Ticked checkboxes on the place, item and where-to-buy forms look nearly empty.

## Buying

8. The Buying notices page is linked only from the morning email; Home has no link.

## Activity page

9. The Season box's arrow overlaps "2026–27".

## Spec differences (decide, then fix code or spec)

- Search results have no photos.
- The item page has an unspecced Recent orders panel.
- Move says "Reason" where Used says "What for?".
- No button to print unit labels.
- Mark all received doesn't put anything into inventory.
- Only buyers can open Buying notices.

## Demo data

`fork/demo_db/orders.rb` picks approvers and buyers from protected mentors (real addresses). Harmless while the demo has no email gateway; keep it that way, or prefer personas.
