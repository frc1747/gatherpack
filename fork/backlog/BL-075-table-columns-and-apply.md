# BL-075: Choose a table's columns, and apply "More choices" without hunting for Show

Two gaps on fork screens with tables:

1. **Choices don't visibly apply.** In the screen kit's filter bar, the Show button sits on the first row, above the "More choices" disclosure. Someone who opens More choices and ticks columns sees no button near the ticks and nothing changes.
2. **Columns are fixed.** Only the form results page lets people pick columns. Every other fork table (reports, rosters, lists) shows every column, on screen and on paper.

## Evidence

- `app/views/shared/_filter_bar.html.erb` (`feature/screen-kit`): `submit_tag "Show"` comes before `<details class="screen-filter-more">`; `auto_submit:` covers only `fields` and the team select.
- `app/views/shared/_people_table.html.erb`: fixed Person column, optional Status, then the caller's columns; no way to hide any.
- Printing is `window.print()` on the page itself everywhere except `inventory/reorder/print` (a separate print template). So a printout already shows what the page shows.

## Fix

**Applying choices (`feature/screen-kit`, `_filter_bar`).** Inside More choices, a change to any field applies at once, the same way `auto_submit:` already does for the team select (Stimulus `filter-bar#submit`, on `change`), for every filter bar that has More choices. A **Show** button also sits at the bottom of the More choices section, for people without JavaScript and for anyone who looks for one. The top-row Show stays as it is.

**Choosing columns (`feature/screen-kit`, new Stimulus controller `column-chooser`).**
- Attach with `data-controller="column-chooser"` on a table's wrapper and a key: `data-column-chooser-key-value="signups-roster"`. It reads the table's `<th>` headings and adds a **Columns** button (`btn btn-sm btn-outline-secondary`, a dropdown of tick boxes, one per heading) at the right of the table's filter bar when there is one (target `data-column-chooser-target="slot"`), else just above the table.
- Unticking hides that column's heading and cells (by column index; cells with `colspan` stay). At least one column stays ticked.
- The choice is remembered per viewer and table key in `localStorage` (try/catch; works without it) and applied on load, so the screen and its Print match.
- A heading with `data-column-chooser-fixed` (such as Person on the people table) can't be hidden and isn't listed.
- `shared/_people_table` gets `choose_columns: <key>` (default `nil`): when given, it wraps the table with the controller and marks the Person column fixed.
- Print: a hidden column is `display: none`, so `window.print()` prints only the ticked columns. The separate `inventory/reorder/print` page uses the same key as the reorder list, so it prints the same columns.

**Adopting it** on every fork table that lists records or results (not edit-form tables such as `checklists/copy_form`, `forms/_edit_questions`, preview pages):
- `feature/checklists`: `checklists/_report`, `checklist_lists/show`
- `feature/commitments`: `commitments/_progress_table`, `commitments/index`
- `feature/signups`: `signup_sheets/roster`, `signup_sheets/index`, `signup_slots/index`
- `feature/orders`: `orders/reports/show`, `orders/funding_sources/report`, `purchases/to_buy`, `funding_sources/index`, `vendors/index`
- `feature/inventory`: `inventory/items/index`, `inventory/reorder/index` and `print`
- `feature/intake`: `intake/registrations/index`, `waiting`
- `feature/forms`: `forms/index` (the results page keeps its own Columns ticks, which also drive CSV)
- `feature/housekeeping`: `housekeeping/index`

Filters stay what each page has today (team, status, search, its More choices).

## Tests

- Kit: system test for `column-chooser` (untick hides heading and cells, survives reload, Person can't be hidden, last column can't be unticked); helper/view test that `choose_columns:` wraps the table; filter bar test that More choices has its own Show and that the change-to-submit wiring is present.
- Each adopting branch: one view assertion that the table carries the controller and key.

## Fork notes

Screen kit change, so every fork branch that uses the kit gets it at merge. gphelp: tables now show a Columns button; retake one example per area.
