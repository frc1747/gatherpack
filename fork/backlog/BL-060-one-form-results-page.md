# BL-060: One page for a form's responses, with fewer buttons

| | |
|---|---|
| Kind | fork-only (feature) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` (`feature/forms` @ `79caab721`) |
| Planned branches | `feature/forms` (the pages are its own); connectors that link to the old pages follow |
| Upstream issue / PR | none |

## Summary

A form's leader sees four screens that all list the same people: the form page (status per person), **Results** (answers per person), **Tally** (counts per choice) and **Printable list** (answers per person again, picked by a population). Users don't know which to open, and it's odd that the status screen isn't the screen with the answers. Merge them into the form page itself: one table of people with their status and answers, the tally as a summary at the top that can be hidden, and print/CSV from the same page. Trim the footer to the actions people actually take.

## Evidence

All in `feature/forms` (fork code), checked at `hbr/integration` `c4700b175`:

- `app/views/forms/show.html.erb:63-90`: footer has up to eleven buttons: Results, Tally, Printable list (all solid primary), Edit, Preview as…, Open/Close, Remind (n), Duplicate, Archive, Delete. The table above it (`:36-58`) shows Person, Status, Version, Submitted, Last reminded, and no answers.
- `app/views/forms/results.html.erb`: Person, Status, one column per question, chosen profile columns (a multi-select, `:22-26`), Version, Signed; team filter, Active/Latest switch, Download CSV (`:86`).
- `app/views/forms/tally.html.erb`: counts for choice and yes/no questions, with a "Who's counted" population picker (`_population_fields`).
- `app/views/forms/print_list.html.erb`: the same answers again, with the same population picker, tick-box columns (answers and profile fields), and Table or Labels layout.
- `app/views/forms/_event_panel.html.erb:33-34`: Results and Tally buttons per form on an event.
- `app/views/form_responses/show.html.erb:118-119`: "See totals" for people the form shares its totals with (`FormPolicy#tally?`, `app/policies/form_policy.rb:19-21`, `forms_controller.rb:176-177` `shared_totals: true`). These people can't see anyone's answers.

## What it does

### 1. The form page is the results page

- Header and description as now.
- **Totals** at the top: the current tally cards, one per choice or yes/no question, counting the people in the table below (same filters). A **Hide totals** link folds them away; the choice is remembered per viewer (browser storage is fine; it's a convenience). Hidden totals don't print.
- **Who's here**: the team filter and status buttons as now (All, Complete, Waiting, …), plus the population picker from the tally/printable list ("Who to include"), shown behind a "More choices" disclosure since most forms never need it.
- **Columns**: tick boxes (not the multi-select) for the form's questions and for profile details, defaulting to every question and no profile details. Status stays as a column; Version, Submitted and Last reminded become one "Submitted" column ("#3 · Nov 20 by Parent") with Last reminded as small text under the status.
- **Show**: Active (submitted) by default; "Latest, including updates in progress" as a second radio choice.
- The table: Person (links to their response), Status, then the ticked columns. Unreadable answers show "·" as the printable list does now.
- **Print** (Table or Labels, a radio choice beside the button) and **Download CSV** act on exactly what's on screen. Print hides the controls; Labels uses the printable-list label layout.

Decision: one page, not tabs. Tabs would keep three screens under one URL; the point is that status and answers are the same list.

### 2. Fewer buttons

Footer, in this order: **Edit**, **Remind (n)** (when open and someone's waiting), **Open** or **Close**. Everything else moves to a **More** dropdown: Preview as…, Duplicate, Archive, Delete. Print and CSV sit with the table (section 1), not in the footer. Event panel rows keep one small **Responses** button (the form page) instead of Results and Tally.

### 3. Old pages

- `results`, `tally` (for managers/readers) and `print_list?form_id=` redirect to the form page with the matching options, so bookmarks and links in emails keep working.
- The standalone Printable list entry point (no form chosen, from the event or menu) stays as a picker that sends you to the chosen form's page.
- **Shared totals stay their own small page.** People the form shares totals with (`tally?` but not `show?`) still get the totals-only view from "See totals"; nothing about who can see what changes.

## Build

1. `FormsController#show` takes the union of the `results`, `tally` and `print_list` params (`team_id`, `status`, `version`, `field_ids[]`, `question_ids[]`, population params, `layout`) and builds one `FormReport` plus the population; `format.csv` moves here from `results`.
2. Move the tally cards into a partial used by both `show` and the shared-totals view.
3. Redirects in `results`, `tally` (when `show?`) and `print_list` (when a form is given).
4. Update links: `_event_panel.html.erb`, `form_responses/show.html.erb`, breadcrumbs, and any connector that links to `results_form_path`/`tally_form_path` (grep `feature/my-gatherpack-forms`, `feature/mcp-forms`, `feature/forms-auto-reminders` and the reminder emails).
5. MCP tools (`form_status`, `form_answers`) are unaffected; check their descriptions don't name the old pages.

No flag: it rearranges `feature/forms`' own screens, which is already behind `feature_forms`. No migration. No hooks (no new events).

## Tests

- Form page shows answers and status in one table; status filter and team filter narrow both the table and the totals.
- Hide totals hides the cards; printing with totals hidden omits them.
- Column tick boxes control table, print and CSV identically; CSV matches the old results CSV for the same options.
- `results`, `tally`, `print_list?form_id=` redirect with options kept.
- A shared-totals viewer still gets totals only, never answers, and is not redirected to the form page.
- Footer shows only Edit / Remind / Open-or-Close for a manager; the More menu holds the rest; a reader without manage sees none of them.

## Fork notes

- Edits only `feature/forms` files and its connectors; no upstream files touched.
- Help site (gphelp) screenshots for Results, Tally and Printable list need retaking after this ships.
