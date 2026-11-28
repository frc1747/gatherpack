# BL-104: Two inventory CSV exports don't guard against spreadsheet formulas

| | |
|---|---|
| Kind | fork bug (`feature/inventory`) |
| Priority | low |
| Status | not started (lead) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | fix on `feature/inventory` |
| Upstream issue / PR | none yet |

## Summary

The Changes and Reorder CSV downloads write item names, reasons, notes and supplier fields as typed. A cell starting with `=`, `+`, `-` or `@` runs as a formula when someone opens the file in a spreadsheet. The other exports (forms, accounting, billing, orders) already guard these cells.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/controllers/inventory/movements_controller.rb:104-113`, `app/controllers/inventory/reorder_controller.rb:95-104`.
- Existing guard: `forms_helper.rb:67,469-472`, `accounting_helper.rb:177-180`, `billing_export.rb:43-47`, `orders/reports.rb:54-60`.

## Proposed fix

Use one shared CSV cell guard (move the existing one into a helper) in both inventory exports.

## Tests

- A stock change note `=HYPERLINK("http://x","c")` exports as `'=HYPERLINK(...)`.
- Normal values unchanged.

## Fork strategy notes

Fork-only; the shared guard can be adopted by the other exports at the next sync.
