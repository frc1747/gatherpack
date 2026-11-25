# BL-074: Form results: totals below the table, Status and Submitted as columns

The form results page (BL-060) shows the Totals section above the table and always shows the Status and Submitted columns. Totals are a summary people read after the rows, and Status and Submitted take room on a printout where only the answers matter.

## Evidence

- `app/views/forms/show.html.erb` (`feature/forms`): Totals render at the top of the card (`render "totals"`, around line 28), before the filter bar and table.
- Same file: `status_cell` is passed as `status:` to `shared/people_table` and `[ "Submitted", submitted_cell ]` is always the first column (around line 145). Neither is in the Columns tick list (`question_ids[]`, `field_ids[]`).
- The "Haven't answered" rows (around lines 148-163) are hand-written to match those columns.

## Fix

- Move the Totals section (with its Hide/Show totals toggle) below the table and the "Haven't answered" rows. Printing keeps the same order.
- Add two ticks at the top of the Columns section's Answers list: **Status** and **Submitted**, ticked by default. They travel like the question ticks (`columns_for` makes the ticks authoritative): new params `show_status` and `show_submitted` (`"1"` when ticked), kept by `show_options`, the filter pills and CSV.
- Unticked Status: don't pass `status:` to the people table, and leave the status cell out of the "Haven't answered" rows. Unticked Submitted: leave the column out of both.
- CSV follows the same ticks (Status and Submitted columns left out when unticked).

## Tests

Controller tests on `forms#show`: totals render after the table; unticking each removes its heading from the table and the CSV; defaults show both; the filter pills keep the choice.

## Fork notes

`feature/forms` only. gphelp: retake the form results screenshot.
