# BL-071: Inventory screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/inventory`, `feature/order-inventory`; after BL-062 |
| Upstream issue / PR | none |

## Summary

An item or place page shows seven to ten buttons (Undo, Edit, Label, Add a place inside, Add an item here, Delete, Count this place…), the unit action pages use large yellow Cancel buttons, the setup page copies upstream's large green Save, and every list repeats links to the other lists as buttons. Keep the phone-first large buttons where people stand at a shelf, and move the rest into the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Item `inventory/items/show.html.erb` | Undo (`btn-dark`), Edit (`btn-warning`), Label, Add where to buy (`btn-secondary`), Delete (`btn-danger`), kind label button | the stock-change buttons (one per kind, `inventory_kind_label`, `:115`) stay together as the page's job group above the history; `_action_row`: Edit, More (Label, Add where to buy, Delete last). Undo becomes the flash's own link after a change, not a footer button |
| Place `inventory/locations/show.html.erb` | Undo, Edit, Add a place inside, Add an item here, Label, Delete, Used, Count this place (`btn-lg`) | `_action_row`: Edit, Count this place, More (Add a place inside, Add an item here, Label, Delete last) |
| Lists `inventory/{items,locations,reorder,search,movements}/index` | each repeats Setup / other-list links as `btn-secondary`; movements has two Print buttons | upstream filter card: New first, Search, Clear Search; links to other lists go (sidebar and breadcrumb already have them); Print and Download CSV once, at the right of the filter bar |
| Unit actions `inventory/units/{move,install,take_off,retire,repaired,mark_for_repair,check}` | Cancel `btn-lg btn-warning`, action `btn-lg` | one-step action page: Cancel `btn-lg btn-secondary`, action `btn-lg btn-primary` (large kept: shelf use on phones) |
| Unit `inventory/units/show.html.erb` | "Edit code and details" `btn-warning`, Undo small | Edit; Undo as above |
| Stock change `inventory/movements/new`, readings, sources, units new/edit | Cancel `btn-warning` (some `btn-lg`) | Cancel `btn-secondary`, Save last; Remove `btn-sm btn-outline-danger` |
| Setup `inventory/setup/show.html.erb` | Save `btn-lg btn-success` (twice), Add a row | sections with one footer: Cancel `btn-secondary`, Save `btn-primary` (pinned, BL-055); Add a row `btn-sm btn-outline-secondary` |
| Labels, reorder print `inventory/labels/show`, `inventory/reorder/print` | Print `btn-primary`, Back to the list; bare table | print view: controls at top, Print `btn-dark`, no Back (breadcrumb); `table-responsive` on screen |

## Works differently

- Item and place pages show Edit, one job and More; Undo moves into the confirmation message.
- Lists no longer repeat links to the other lists.

## Tests

- Item and place pages: footer has Edit, the job and More; Delete last in More with its confirm; Undo link appears in the flash after a stock change and works.
- Unit actions still submit; Cancel returns to the unit.
- Setup saves with one footer.
- Existing inventory and order-inventory tests stay green; none weakened (update selectors that found Undo in the footer).

## Fork notes

- No flag (`feature_inventory` gates it). No upstream files touched.
- Retake gphelp screenshots: item, place, unit actions, setup, lists.
