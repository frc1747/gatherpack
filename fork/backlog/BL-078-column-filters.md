# BL-078: Sort and filter any fork table by its columns

People reading a fork table (form results, rosters, order reports) can hide columns (BL-075) but can't narrow the rows by a column's value or sort by it. The checklist report already does both in its headings (`checklist_report_controller.js`: click a heading to sort; a funnel menu ticks which values to show), but only for itself.

## Fix

A shared Stimulus controller on `feature/screen-kit`, `table-filter`, attached wherever the Columns chooser is: `ScreenKitHelper#column_chooser_data` and `shared/_people_table` `choose_columns:` add it next to `column-chooser`, so every table that has Columns gets it with no change on the adopting branches.

- **Sort:** clicking a heading's name sorts its rows; again reverses. Order: a cell's `data-sort-value` if present, else its text, numbers and dates compared as such. Rows sort within their own `tbody`. An arrow shows the column and direction.
- **Filter:** each filterable heading gets a small funnel button. Its menu lists the column's distinct values with counts ("(blank)" for empty cells), tick to show only rows with any of them. A column with more than 12 distinct values gets a "Contains…" text box instead. Filters on several columns combine (all must match). The funnel is filled while that column filters.
- **Clear:** a "Clear filters" link next to the Columns button while any filter is on.
- **Not filterable or sortable:** headings with no text, headings marked `data-table-filter-skip`, and columns whose cells hold form inputs (tick boxes, quantities). A wrapper with `data-table-filter="off"` gets nothing (the checklist report keeps its own richer controls).
- **Print** shows rows as filtered and sorted (hidden rows are `d-none`). Filters and sort are not remembered across visits; columns are.
- Works with several tables in one wrapper (sections): the menus list values across all of them and filter each.

## Tests

Kit system tests: sort both ways (text and numbers), tick filter, contains filter past 12 values, two filters combine, Clear filters, input columns and skip-marked headings get no funnel, `data-table-filter="off"` gets nothing, sections filter together. Helper test: the data helper and `choose_columns:` attach both controllers.

## Fork notes

`feature/checklists` marks its report wrapper `data-table-filter="off"`. gphelp: one screenshot of a filtered table.
