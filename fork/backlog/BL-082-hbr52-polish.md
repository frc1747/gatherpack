# BL-082: hbr.52 polish: wording, a breadcrumb, shared columns and a team picker

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | low |
| Status | open |
| Added | 2026-11-22 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | one fix per owning branch, listed below |
| Upstream issue / PR | none |

## Summary

The help site's hbr.52 review found places where hbr.52 doesn't match its backlog items or reads badly. Each is small. Some are by design; those are recorded as decisions so nobody "fixes" them.

## Fixes

| # | What people see | Cause | Fix | Branch |
|---|---|---|---|---|
| 1 | Copying a checklist says "The copy starts as a draft", but checklists call this **Counting: Not yet** | `app/views/checklists/copy_form.html.erb:68`; notice at `app/controllers/checklists_controller.rb:95` | "The copy starts with Counting set to Not yet." and "Duplicated. Counting is Not yet: check it, then turn it on." | `feature/checklists` |
| 2 | The reorder list's **Columns** choice doesn't carry to its print page (BL-075 says it does) | different keys: `inventory/reorder/index.html.erb:36` `"inventory-reorder"`, `inventory/reorder/print.html.erb:5` `"inventory-reorder-print"` | Use `"inventory-reorder"` on both; the chooser stores headings, so differing columns are fine | `feature/inventory` |
| 3 | On form results, **Download CSV**, **Labels** and **Totals** use every row even after the heading filters narrow the table; Print uses the filtered rows | heading filters are client-side; CSV is built from `@rows` (`app/controllers/forms_controller.rb:77-78`) | They follow what's on screen: the buttons send the active heading filters and sort, and the server applies them. One rule for all four | `feature/forms` (kit part in `feature/screen-kit`) |
| 4 | Settings shows the whole default print stylesheet as the **Default:** text for Print style | `settings/index.html.erb:48` prints `default_value`; the default is all of `print_default.css` | A `SettingInput` for `print_css` whose default label is "The standard print style" | `feature/print-style` |
| 5 | A checklist's status buttons read "Not eligible" next to "Not Eligible" | sample data sets "Not eligible" (`fork/sample_data/features/checklists.rb:178`); defaults and hints are Title Case | Sample data uses "Not Eligible" | `hbr/platform` |
| 6 | A form response's breadcrumb skips the form: Home › Forms › "Form: Person" | `config/breadcrumbs/form.rb:31-34` `crumb :form_response` has `parent :forms` | `parent :form, response.form`; check the other response crumbs in that file | `feature/forms` |
| 7 | "Waiting for a leader, recording a paper signature's signature" | `FormQuestion::SIGNER_DESCRIPTIONS` (`app/models/form_question.rb:85`) is a clause; `form_submission.rb:100` and `checklists/kinds/form_complete.rb:270-282` append "'s signature" | A second, short noun per signer for waiting text: "a leader's signature (paper)" | `feature/forms`; checklist half in `feature/checklists-connectors` |
| 8 | **Other teams form creators can ask** is a one-team-per-line text box marked required, though blank is allowed | registered as `:text` (`lib/settings.rb:203`); simple_form marks it required | A team picker setting storing team ids (`SettingInput::Teams`, as `feature/settings-inputs` does elsewhere); `Form.creator_extra_audience_team_ids` (`app/models/form.rb:117-123`) reads ids, and a data migration turns today's names into ids. A list of teams typed as text breaks AGENT.md rule 13 | `feature/forms` |
| 9 | On a checklist's **Reminders** tab, an item's "What reminders may say" select draws its arrow over "Same as the checklist" | `app/views/checklist_reminders/_setup.html.erb:37-39`: `form-select form-select-sm w-auto` in a table cell; `w-auto` sizes to the text and leaves no room for the arrow's padding | Drop `w-auto`; give the cell a `min-width` (about 14rem) so the select is full width of a cell wide enough for its longest choice | `feature/checklists-reminders` |
| 10 | The Reminders tab offers "Send through the summary email…" while Summaries is off | `Checklists::ReminderDigest.available?` (`app/models/checklists/reminder_digest.rb:12-14`) checks only that the digests code is loaded, not `feature_digests` | `available?` also requires `GatherPack::Features.enabled?(:digests)`; the same check covers `delivery_for` (line 19), so reminders go by plain email while Summaries is off | `feature/checklists-reminders` |

## Decisions (no change)

- **Event Duplicate** opens a prefilled New event page and saves nothing until Create Event (`app/controllers/concerns/events_duplicating.rb:9-14`). An event needs its new date before it exists, so this is right; the screen standard in `fork-spec` now says so.
- **Checklist Duplicate** names the copy with the years moved on and opens it, instead of "(copy)" (`app/views/checklists/copy_form.html.erb:17`, `copier.rb:93`). A season copy named "(copy)" would only be renamed; `fork-spec` now says so.
- **Discard draft** is a button on desktop and in More on phones (`form_responses/show.html.erb:108`). That's the phone rule in `fork/specs/screen-standard-spec.md` (keep the first action and More).
- **Commitment pages** fold into Checklists while Checklists is on (`app/controllers/concerns/commitments_to_checklists.rb:19-30`, checklists spec §11.3): the list and a person's commitments go to checklists, and a commitment counted by a checklist item opens its checklist. Commitments outside a checklist keep their own pages with hbr.52's Remind, Columns and Duplicate. That's the design: the checklist, which now has reminders and columns, is the one place for counted work.

## Tests

Each fix with its branch's tests: the copy wording (1), one shared column key (2), a CSV of a filtered table having only the filtered rows (3), the Settings page not printing the stylesheet (4), the response breadcrumb including the form (6), the waiting text (7), the team picker saving ids and the migration converting names (8), and, with Summaries off, no summary tick box on the Reminders tab and reminders sent as plain email (10).

## Fork notes

All fork-only. No upstream files beyond `lib/settings.rb` (8), which `feature/forms` already touches.
