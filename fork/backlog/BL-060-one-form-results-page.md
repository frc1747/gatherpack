# BL-060: One page for a form's responses, with fewer buttons

| | |
|---|---|
| Kind | fork-only (feature) |
| Priority | medium |
| Status | done (feature/forms, not yet released) |
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

### 2. Fewer buttons, each where its job is

Leaders were afraid to press **Open** because nothing said what it did (send an email? lock the questions?). Fix it with placement and plain labels, not a description beside the button.

- **Taking answers moves into the form's setup.** The Open and Close buttons leave the footer. The Edit page's "When people can respond" section (`_responses_fields.html.erb`, beside Opens and Deadline) gets one radio choice, **Taking answers**:
  - **Not yet**: only people who manage the form can see it (today's draft).
  - **Yes, open now**: it appears in My forms for the people it asks.
  - **No, closed**: people can still read their answers but can't add or change them (leaders still can, when late entries are on).
  Saved with the rest of the page. Opening doesn't email anyone (checked: no hook or notice fires on the status change); reminders are separate. The Opens and Deadline times sit right under it, so "opens itself at this time" reads as the automatic version of the same choice.
- **The form page says where it stands** in the header, in words: "Not taking answers yet", "Taking answers until Nov 30" or "Closed Nov 30", replacing the bare Draft/Open badge. When the form isn't open, that line links to the setting ("Start taking answers").
- **Footer**, in this order: **Edit** (`btn-warning`), **Remind (n)** (`btn-primary`, the page's job; when taking answers and someone's waiting). Everything else goes in a **More** dropdown (`btn-secondary`): Preview as…, Duplicate, Archive, Delete (last). Print (`btn-dark`) and Download CSV (`btn-secondary`) sit at the right of the filters above the table (section 1), not in the footer.
- **The Edit page's footer** becomes Cancel (`btn-secondary`), Save; today it says "Back" in `btn-warning` (`forms/edit.html.erb:40`).
- Words and styles follow the screen standard (`fork-spec` "Screen design", gp-map "Views"). The screen kit ([BL-062](BL-062-screen-kit.md)) may not exist yet: write the same markup by hand; [BL-064](BL-064-screens-forms.md) swaps it for the kit's partials.
- Event panel rows keep one small **Responses** button (the form page) instead of Results and Tally.

The open/close routes stay (MCP and the auto-open job use the same status); only the buttons go.

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
- Footer shows only Edit and Remind for a manager; the More menu holds the rest; a reader without manage sees none of them.
- Taking answers on the Edit page: choosing "Yes, open now" on a form with nobody to ask shows the existing "Add someone to ask" error by the field and doesn't open it; each choice sets the status; the header line matches the status and deadline.

## Fork notes

- Edits only `feature/forms` files and its connectors; no upstream files touched.
- Help site (gphelp) screenshots for Results, Tally and Printable list need retaking after this ships.
