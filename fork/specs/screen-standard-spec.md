# Screen standard

One way to lay out each kind of screen, so that someone who has learned one feature already knows the next. The rules themselves live in the `fork-spec` skill ("Screen design") and the button table in the `gp-map` skill ("Views"); this spec holds the reasoning, the shared partials, the fix-up plan, how upstream's screens are treated, and the inventory it was all drawn from. Source: [BL-061](../backlog/BL-061-screen-audit-and-standard.md).

Checked at `hbr/integration` `c4700b175`. The inventory appendix is a working table: delete it once the fix-up items (BL-062 to BL-073) ship.

## What the audit found

Every page template in the integration build was read by a script (395 templates: the 382 in `app/views`, the 4 pages replaced in `app/view_overrides`, and 9 partials that render a whole section, such as event panels and profile tabs; emails, layouts and Turbo stream responses are listed but not judged). 361 are screens people see: 123 pure upstream, 54 upstream with fork edits, 184 fork-only.

| Finding | Count | Examples |
|---|---|---|
| Pages with more than three action buttons (layers 1-2, counting buttons that only show in some states) | 43 (23 fork) | `orders/requests/show` 23, `forms/show` 13, `form_responses/show` 11, `inventory/locations/show` 10, `signup_sheets/show` 8; upstream `questions/show` 29, `events/show` 12, `ledgers/show` 11 |
| More menus | 0 | 32 dropdowns, all for sorting or filtering lists, never for actions |
| "Edit" styles | 5 | `btn-warning` 49, small row buttons 13, `btn-primary` 2, `btn-secondary` 1, `btn-link` 1; fork also says "Set up" (Sign-ups, Commitments) and "Edit code and details" |
| "Cancel" styles | 5 | `btn-warning` 112 (same colour as Edit), `btn-link` 8, `btn-primary` 4, `btn-danger` 4, outline 3 |
| Form footer order | | upstream puts Cancel before Save in 71 forms, Save first in 3; fork forms mix both |
| Open/closed state changed by a button | 3 pages | Forms Open/Close, Intake "Close now", Questions Reopen/Close (upstream). The script flagged 11 more pages; those are lifecycle actions (Archive, Restore, Retire), decisions (Approve, Withdraw) or a modal's Close, which the standard keeps as buttons |
| State changed by a bare select | 2 | Sign-up sheet and Checklist status selects (Draft / Open / Closed / Archived, no effect said) |
| Browser `turbo_confirm` dialogs | 70 pages | upstream mostly "Are you sure?"; fork mostly names the effect |
| Record parts as tabs | 3 | `people/_show_shared`, `teams/_show_shared` (link tabs), `forms/edit` (link tabs per part) |
| Long setup pages that stack every part | 3 | `signup_sheets/edit` (form, then positions, dates, slots, organizers, audience), `checklists/edit` (form, then items, rules, access), `commitments/edit` |
| Lists or records without breadcrumbs | 9 | all five `intake/registrations` pages, `ledger_payments/new`, `order_inventory/reorder_drafts/new`, `orders/vendors/pattern_test`, `share/show` |
| Tables without `table-responsive` | 19 | all fork (Forms tally, Intake registrations, Housekeeping, Sign-up sheet list, Commitments list, Theme palette preview `theme_previews/show`); none upstream |
| Settings forms on reading screens | 0 real | Filters only; `notification_settings` is a person's own settings page |
| Own footer styles | 2 | `orders/settings` and `inventory/setup` copy upstream's Settings page (`btn-lg btn-success` Save, `btn-lg btn-primary` Cancel) |

What already works and is kept: upstream's header card (title in `h1`, `card-header`), its list filter card (fields, then New / Search / Clear Search in the footer), its record footer (Edit first, Delete last), breadcrumbs on almost every page, My GatherPack's rows (`mg-row`, one solid action, the rest outline), and the pinned form buttons from BL-055.

### Visual check

Code only. `demo.hbrlive.com` asked for a sign-in this session, which an agent may not complete. Look at these screens in the installed Chrome (desktop and phone width, signed in as each audience) when a fix-up item is picked up, and add anything the code didn't show to that item:

| Audience | Layer 1 | Layer 2 | Layer 3 | Layer 4-5 | Phone |
|---|---|---|---|---|---|
| Admin | People | Event page with its panels | Form edit, Questions tab | Setup page; Orders settings | Event page |
| Leader (team manager) | Sign-up sheet Roster | Form page; Checklist page | Sign-up sheet setup page | Inventory setup | Form page, Roster |
| Member | Home | Sign-up sheet; their form response | Sign up | none | Home, Sign-up sheet |
| Guardian | Home (family) | Family page; a ward's response | Fill in for a ward | none | Family page |

## The standard

The rules are in `fork-spec` "Screen design" (shape, placement, state, confirmation, configuration, navigation, phone) and `gp-map` "Views" (words and styles). The reasoning behind the choices that weren't obvious:

- **Keep upstream's colours where upstream is consistent, change only the clash.** Upstream's Edit is yellow on 49 pages and its New is green on every list; changing those means editing dozens of upstream views for no gain in clarity. The real problem is Cancel sharing Edit's yellow. Cancel becomes grey (`btn-secondary`) everywhere: in fork views directly, and on upstream forms by the screen kit's stylesheet (see "Upstream screens").
- **Forms end Cancel, then Save.** Upstream does it in 71 of 74 forms; the main button ends the row where the eye finishes. Action rows on lists and records start with their most-used action instead (Edit, then the page's job). Both are the same idea: the main button is where people look first for that kind of screen.
- **Delete is last.** When a page has a More menu, Delete is its last item. A page with three actions or fewer and no More menu shows Delete as the last button in red, as upstream's record pages do. Fork pages with a More menu never show Delete outside it.
- **Table actions sit with the table.** Print and Download CSV act on what the table shows, so they sit at the right of the filter bar above it, not in the page footer (BL-060's pattern).
- **States are settings; lifecycle and decisions are buttons.** Whether something is open, published or counting is part of how it's set up, so it's a labelled choice on its Edit page ("Taking sign-ups: Not yet / Yes, open now / No, closed"), and the record page says the state in words. Archiving and restoring end or resume a record's life rather than tune it, so they're actions: the last items in More before Delete, each with a confirm naming the effect ("Archive this sheet? It's hidden from lists; sign-ups are kept."), on their own routes, never the `DELETE` route. Deciding on someone's request (Approve, Decline, Ask for changes) is the job of the record page for the person whose turn it is, so it stays a button, labelled with the effect.
- **Browser dialogs stay for one-click actions.** An inline question needs a form to live in. Delete, Archive, Remove, Withdraw and Cancel request are single buttons with no form, so they keep `turbo_confirm`, and the dialog names the effect ("Delete this event and its 12 check-ins?"), never "Are you sure?". Everything that saves a form asks inline, above Save.
- **Parts as tabs only past two.** A record with more than two parts (a person: overview, teams, relationships, forms…) gets link tabs, one URL per tab, like `people/_show_shared`. A setup page with more than two parts (a sign-up sheet: details, positions, dates, organizers, who can sign up) gets the same tabs, as `forms/edit` does. Fewer parts stay on one page.

### Sketches

Layer 1, list (upstream `badges/index`, fork `checklists/index`):

```
Home > Checklists
+--------------------------------------------------------------+
| Checklists                                                   |
| What each person still needs to finish this season.          |
|--------------------------------------------------------------|
| Name [______]  Team [All teams v]  Status [Active v]         |
|--------------------------------------------------------------|
| [New Checklist]  [Search]  [Clear Search]                    |
+--------------------------------------------------------------+
| Title              Team        Status      Updated           |
| Safety training    Northwind   Active      Nov 20            |
| ...                (table-responsive; "Nothing here yet.")   |
```

Layer 2, record (BL-060's form page is the worked example):

```
Home > Forms > Field trip permission
+--------------------------------------------------------------+
| Field trip permission                                        |
| Asks Northwind Robotics · due Nov 30                         |
| Taking answers until Nov 30                    <- state line |
|--------------------------------------------------------------|
| [Hide totals]  totals cards ...                              |
| Team [All v]  All (24) Complete (18) Waiting (6)             |
|   > More choices                     [Print] [Download CSV]  |
| Person            Status      Answers ...                    |
|--------------------------------------------------------------|
| [Edit]  [Remind (6)]  [More v]                               |
|                        Preview as… / Duplicate / Archive /   |
|                        Delete                                |
+--------------------------------------------------------------+
```

With more than two parts, link tabs sit right under the header card (`people/_show_shared`).

Layer 3, edit (upstream `badges/edit`, fork `forms/edit` with tabs):

```
Home > Forms > Field trip permission > Edit
+--------------------------------------------------------------+
| Editing Field trip permission                                |
| Details | Questions (6) | Who is asked (24) | Permissions    | <- tabs past two parts
|--------------------------------------------------------------|
| Taking answers                                               |
|  ( ) Not yet: only people who manage the form can see it     |
|  (•) Yes, open now: it appears in My forms for people asked  |
|  ( ) No, closed: people can read their answers, not change   |
| Opens [____]  Deadline [____]                                |
|   > More choices                                             |
|--------------------------------------------------------------|
| 3 people have answered. Change their answers too?            | <- inline question,
|  (•) No, keep them  ( ) Yes                                  |    only when needed
| [Cancel]  [Save]                          (pinned, BL-055)   |
+--------------------------------------------------------------+
```

Layer 4, feature setup: the main Setup page lists each feature's things under its heading (upstream's `welcome/setup`). A vocabulary table (`managed_lists/index`, Badge Types) is a list page: New first, rows with small Edit, arrows, Retire. A feature-wide settings page (`orders/settings`, `inventory/setup`) is an edit page: sections, then Cancel / Save.

Layer 5, site settings: upstream's Settings, Theme and Gateways pages, left as upstream draws them.

Other kinds:

- **Print view**: no navigation; the controls (layout choice, Print button) at the top and hidden when printing (`no-print`); the page's own title.
- **One-step action page** ("wizard": Move a unit, Copy a checklist, Merge people): header card with the thing it acts on, the one question, then Cancel and a button named for the effect ("Move", "Copy", "Merge"). A multi-step flow says the step ("Step 2 of 3") and uses Back (`btn-secondary`) for the previous step.
- **My GatherPack card or row**: one solid action per row, other actions outline (`btn-outline-secondary`); no More menu (the row is the menu).
- **Public pages** (join, verify, guardian confirm): one card, one primary button, no navigation.
- **Kiosk**: its own large-button layout; out of this standard except words.
- **Email**: one link button at most; words match the screen it opens.

### Phone width

- The action row keeps its first action and More; the other visible actions move into More (`d-none d-md-inline` on the button, the same item `d-md-none` in the menu). The screen kit's action row does this from one list.
- Tables scroll sideways inside `table-responsive`; the first column (usually the person) stays. Cards in place of tables only where a screen already has them (People, My GatherPack).
- Filters collapse behind a "Search" or "Filters" button, as People does (`people/index` `d-md-none` toggle).
- Pinned form buttons sit above the phone tab bar (BL-055).

## Screen kit (shared partials)

Built once on `feature/screen-kit` from `upstream/main`, before any fix-up item (BL-062). Plain partials and one helper, no models, no flag for the partials themselves (they change nothing until a view renders them).

| Partial | Renders | Locals |
|---|---|---|
| `shared/_page_header` | Header card top: `h1` title, one-line summary, state line, optional tabs | `title:`, `summary:`, `state:` (a `state_line` result), `tabs:` (array of `[label, path]`) |
| `shared/_state_line` | The current state in words ("Taking answers until Nov 30"), muted, with an optional link to the setting ("Start taking answers") | `text:`, `link_text:`, `link_path:` |
| `shared/_action_row` | Card footer: up to three visible buttons, then **More** (`btn btn-secondary dropdown-toggle`) holding the rest. Lifecycle actions (Archive, Restore) and actions built with `more: true` always go in More, even with three actions or fewer; when that makes a More, destructive items go in it too. More lists ordinary items, then lifecycle, then destructive last (`text-danger`). With no More, Delete is the last button, `btn-danger`. On phone only the first action and More stay out | `actions:` (array of `ScreenKit::Action`) |
| `shared/_inline_confirm` | The question just above Save, radio choices inline, safe default selected, applied by the save | `question:`, `name:`, `choices:`, `selected:` |
| `shared/_filter_bar` | Optional extra fields, team filter, status pills with counts, a "More choices" disclosure for rare filters, and table actions (Print, Download CSV) at the right | `url:`, `teams:`, `team:`, `all_teams_label:` (the blank team choice, default "All teams"), `statuses:`, `status:`, `params:` (the page's other options, kept by the pills, and by Show unless `hidden:` is given), `hidden:` (what Show keeps instead, when More choices fields already carry some options), `fields:` (HTML always shown in the Show form, before the pills, e.g. a season select), `more:`, `open:` (More choices starts open), `table_actions:` (`screen_action`s, including path-less script buttons), `table_actions_html:` (other table controls, e.g. a Table/Labels choice), `form_id:` (the Show form's id, for outside inputs' `form:`), `auto_submit:` (true: a change to the fields or team applies at once and Show is hidden; Show stays without JavaScript and while More choices is there); its button is Show |
| `shared/_people_table` | `table-responsive` table: Person (linked), Status (badge in the feature's words), then the caller's columns; empty state | `rows:`, `columns:` (`[header, ->(row) { cell }]`, optional third item: HTML options for the `th` and `td`s), `empty:` ("Nobody here."), `person:`, `link:` (where the name goes; nil, or a lambda returning nil, for a plain name), `status:`, `table_class:` (default `table table-striped align-middle`), `wrapper:` (HTML options for the scrolling wrapper: id, data, extra class), `rows_after:` (more rows at the end of the body, e.g. a "Haven't answered" group; the table shows even with no rows) |
| `shared/_empty_state` | One muted line, optionally a button to add the first one | `text:`, `action:` |
| `shared/_record_tabs` | Link tabs (`nav nav-underline`), one URL per tab, active by current page | `tabs:` |

Helper `ScreenKitHelper` (`app/helpers/screen_kit_helper.rb`): `screen_action(label, path, style: :secondary, method: :get, confirm: nil, visible: true, lifecycle: false, destructive: false, more: false, data: {})` builds a `ScreenKit::Action`. In More come ordinary items, then lifecycle items such as Archive and Restore (not red, each with a confirm naming the effect), then destructive items last, `text-danger`. `lifecycle:` and `more: true` always put the action in More. `data:` goes on the rendered link or button. A nil `path` renders a plain `<button type="button">` for page script (Print with `data: { action: "form-results#print" }`), as a row button, a More item or a table action. With three actions or fewer and no More, a phone-only More holds the buttons hidden at phone width. Also `state_line(text, link_text: nil, link_path: nil)`.

Stylesheet `screen_kit.css`, linked from the layout only while `feature_screen_standard` is on ("Standard buttons on built-in screens", default off): restyles Cancel on upstream forms as `btn-secondary` with one selector, `main form .card-footer > a.btn-warning:has(+ [type=submit])`: a yellow link directly before the submit, which is where upstream's 71 forms put Cancel (the same `:has()` approach as BL-055). It leaves other yellow links alone, such as Edit in `mailboxes/show`'s footer, which sits beside a search submit. This is the one look change to upstream screens, so it has the flag.

Manifest position of `feature/screen-kit`: **open, for Corey.** It depends only on `upstream/main`; every fix-up branch depends on it.

## Plan

In order. Each item lists its screens, the changes, tests and the gphelp screenshots to retake. Fork changes go on the feature's own branch, behind no new flag (they rearrange the feature's own screens); a change that makes a screen work differently is called out in the item and the HBR changelog.

| Order | Item | Branch(es) | Why here |
|---|---|---|---|
| 1 | [BL-062](../backlog/BL-062-screen-kit.md) Screen kit | new `feature/screen-kit` | every fix-up uses it |
| 2 | [BL-060](../backlog/BL-060-one-form-results-page.md) One form results page | `feature/forms` | the worked example (already in progress; moves onto the kit in BL-064) |
| 3 | [BL-063](../backlog/BL-063-screens-home.md) Home and My GatherPack | `feature/my-gatherpack*` | every member and guardian |
| 4 | [BL-064](../backlog/BL-064-screens-forms.md) Forms, the rest | `feature/forms`, `feature/my-gatherpack-forms` | members fill in, leaders read |
| 5 | [BL-065](../backlog/BL-065-screens-signups.md) Sign-ups | `feature/signups` (+ `signup-credit`, `checklists-connectors` panels) | members sign up |
| 6 | [BL-066](../backlog/BL-066-screens-checklists.md) Checklists | `feature/checklists`, `feature/checklists-connectors` | members and guardians read |
| 7 | [BL-067](../backlog/BL-067-screens-events.md) Event panels | `feature/forms`, `feature/signups`, `feature/event-type-checkin-fields` | everyone opens events |
| 8 | [BL-068](../backlog/BL-068-screens-profiles.md) People and Teams profiles | `feature/profile-tabs` and the tabs' features, `feature/intake` | leaders and members |
| 9 | [BL-069](../backlog/BL-069-screens-orders.md) Orders | `feature/orders`, `feature/order-inventory` | members request |
| 10 | [BL-070](../backlog/BL-070-screens-commitments.md) Commitments | `feature/commitments` | members read on their profile |
| 11 | [BL-071](../backlog/BL-071-screens-inventory.md) Inventory | `feature/inventory` | members search |
| 12 | [BL-072](../backlog/BL-072-screens-intake.md) Intake (leader side) | `feature/intake`, `feature/intake-checklist` | setup only |
| 13 | [BL-073](../backlog/BL-073-screens-setup-only.md) Setup-only screens | `feature/person-fields`, `feature/managed-lists`, `feature/housekeeping`, `feature/widgets`, `feature/mcp`, `feature/person-merge`, `feature/phone-notifications` | admins only |

### BL-060 against the standard

BL-060 already follows it: state line in words, Taking answers as a labelled choice on the Edit page, footer Edit then Remind then More (Preview as…, Duplicate, Archive, Delete), Print and Download CSV with the table, rare filters behind "More choices", tick boxes for columns, one small "Responses" row button on event panels. Two lines were added to BL-060: Remind is the page's job button (`btn-primary`) and Edit stays `btn-warning`; and the Edit page's footer becomes Cancel, Save (it says "Back" in `btn-warning` today). BL-060 is built before the kit exists, so it writes plain markup in the kit's shape; BL-064 swaps it for the partials.

## Upstream screens

Each difference between upstream's screens and the standard, and what happens to it.

| Difference | Where | Class | Cost or note |
|---|---|---|---|
| Header card with `h1`, list filter card, New / Search / Clear Search footer | every upstream list | **Fork matches upstream** | the standard is upstream's shape |
| Edit `btn-warning` first, Delete `btn-danger` last, no More menu on short footers | 19 record and type pages (`badges/show`, `event_types/show` …) | **Fork matches upstream** | rule allows a visible Delete when there's no More menu |
| Forms end Cancel, then Save | 71 forms | **Fork matches upstream** | |
| Cancel in `btn-warning` | 112 upstream forms | **Fork wrapper** | `screen_kit.css` under `feature_screen_standard`; no view edits |
| Settings page Save `btn-lg btn-success`, Cancel `btn-lg btn-primary` | `settings/index` | **Fork matches upstream** | one admin page; fork setup pages stop copying it (BL-069, BL-071) |
| "Are you sure?" dialog wording | 48 upstream dialogs | **Fork matches upstream** | wording only; not worth an edit each |
| More than three actions on a record | `events/show` (Print, Arrange, Edit, Delete) | **Upstream edit** | 1 file, already in FORK.md for panels; Edit, Print, More (Arrange, Delete). For Corey to approve |
| | `people/show` (Impersonate, Edit Profile, Change Email, …) | **Upstream edit** | 1 file, already touched by person-fields; Edit Profile first, rest in More. For Corey to approve |
| | `teams/show`, `ledgers/show`, `ledger_entries/show`, `budgets/show`, `time_clock_periods/show`, `calendar/index`, `questions/show` | **Fork matches upstream** | setup-audience or rarely used; not worth new upstream divergence |
| Open/Close as buttons | `questions/show` (Reopen, Close) | **Fork matches upstream** | upstream Q&A only; not a fork feature |
| "Edit Profile" instead of "Edit" | `people/show` | **Upstream edit** | with the `people/show` edit above |
| No breadcrumb | `ledger_payments/new` (Pay Into a ledger, reached only from the ledger's page) | **Fork matches upstream** | left as is: adding one `breadcrumb` line would be a new upstream edit for one rarely used admin page |

No change here assumes anything is offered upstream; that's Corey's call per change.

## Hooks

None. Screens only; no models or events.

## Appendix: inventory

One row per template in `hbr/integration` `c4700b175`, generated from the views (actions in source order, including buttons that show only in some states). Screenshot column omitted: the visual check was code only (see "Visual check").

Key: **Owner** = fork branch that added it, `upstream`, or `upstream*` (upstream file with fork edits). **L** = layer 1 list, 2 record, 3 edit, 4 feature setup, 5 site, or another kind. **Aud** = read (members, guardians, readers), set (leaders, admins), both. **Hdr** = `h1`, `s` summary line, `b` status badge. **Actions** = where they sit, then each label with its style: `P` primary, `S` secondary, `G` success, `D` danger, `W` warning, `I` info, `K` dark, `L` link, `Lt` light, `o` outline, `s` small, `+` large, `m` dropdown item; `Save*` is a default submit label; (n) = action buttons in the template, then row buttons. **Extra** = `dd` dropdown (none is a More menu). **State** = buttons that change state. **Confirm** = browser dialogs. **Lists** = filters, tables, tabs, shared partials. **Crumb** = breadcrumb.

| Template | Owner | L | Aud | Hdr | Actions (where: words+style) | Extra | State | Confirm | Lists | Crumb |
|---|---|---|---|---|---|---|---|---|---|---|
| `announcement_mailer/announcement` | upstream | email | read | h1 | - | - | - | - | - | n |
| `announcement_mailer/announcement.text` | upstream | email | read | - | - | - | - | - | - | n |
| `announcements/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `announcements/index` | upstream* | 1 | read | h1b | footer+body: New Announcement·G, Search·P, Clear Search·K, (submit)·oP (4) | dd | - | - | filter, bar | y |
| `announcements/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `announcements/show` | upstream* | 2 | read | h1b | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `audit_logs/index` | upstream | 5 | set | h1 | footer: Search·P, Clear Search·K (2) | dd | - | - | filter | y |
| `audit_logs/show` | upstream* | 5 | set | h1s | footer: Revert·W (1) | - | - | x1 | table-resp | y |
| `authorized_applications/index` | security-series | 5 | set | h1 | - | - | - | x1 | table-resp | y |
| `badge_assignments/candidates` | search-and-add | misc | both | -b | - | - | - | - | add_candidates | n |
| `badge_assignments/create.turbo_stream` | search-and-add | stream | both | -b | - | - | - | - | - | n |
| `badge_assignments/destroy.turbo_stream` | search-and-add | stream | both | -b | - | - | - | - | - | n |
| `badge_assignments/index` | upstream* | 1 | both | h1b | - | - | - | - | add_candidates | y |
| `badge_assignments/new` | upstream | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `badge_assignments/show` | upstream* | 2 | both | h1b | footer: Delete·D (1) | - | - | x1 | - | y |
| `badge_types/edit` | upstream | 4 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `badge_types/index` | upstream | 4 | set | h1b | footer: New Badge Type·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `badge_types/new` | upstream | 4 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `badge_types/show` | upstream | 4 | set | h1b | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `badges/edit` | upstream | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `badges/index` | upstream | 1 | both | h1b | footer: New Badge·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `badges/new` | upstream | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `badges/show` | upstream* | 2 | both | h1b | footer: Edit·W, Manage Assignments·I, Delete·D (3) | - | - | x1 | - | y |
| `budget_periods/edit` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `budget_periods/index` | upstream | 4 | set | h1 | footer: New Budget Period·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `budget_periods/new` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `budget_periods/show` | upstream | 4 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `budgets/edit` | upstream | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `budgets/index` | upstream* | 1 | set | h1 | footer: Budget Periods·S, New Budget·G, Search·P, Clear Search·K (4) | dd | - | - | filter | y |
| `budgets/new` | upstream | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `budgets/show` | upstream* | 2 | set | h1b | body+footer: Edit·W, Delete·D, i·Ks, i·Ws, i·Is, i·Ws +1 (7) | - | - | x2 | - | y |
| `calendar/index` | upstream | 1 | read | h1 | footer: New Event·G, New Note·G, (submit)·P, Clear Search·K, All Events·I, All Notes·I +4 (10) | - | Close | - | filter | y |
| `calendar_notes/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `calendar_notes/index` | upstream* | 1 | set | h1 | footer: New Calendar Note·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `calendar_notes/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `calendar_notes/show` | upstream* | 2 | set | h1b | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `checkin_fields/edit` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `checkin_fields/index` | upstream | 4 | set | h1 | footer: New Checkin Field·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `checkin_fields/new` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `checkin_fields/show` | upstream* | 4 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `checkins/candidates` | search-and-add | misc | set | - | - | - | - | - | add_candidates | n |
| `checkins/create.turbo_stream` | search-and-add | stream | set | - | - | - | - | - | - | n |
| `checkins/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `checkins/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `checkins/show` | upstream* | 2 | set | h1 | footer: Edit·W, Checkout·D (2) | - | - | x1 | - | y |
| `checklist_excuses/meeting` | checklists | 1 | set | h1b | body+footer: Remove·Ls, Save*·P, Cancel·L (3) | - | - | - | - | y |
| `checklist_excuses/new` | checklists | 3 | set | h1 | body: Save*·P, Cancel·L (2) | - | - | - | - | y |
| `checklist_items/edit.html+count` | checklists-connectors | 3 | set | h1b | body: Save anyway·Ws, Save*·P, Cancel·L, Remove·Ls, Add rule·Ps, Add …·S +1 (7; 1 row) | - | - | x2 | - | y |
| `checklist_items/edit` | checklists | 3 | set | h1b | body: Save anyway·Ws, Save*·P, Cancel·L, Remove·Ls, Add rule·Ps (5) | - | - | - | - | y |
| `checklist_items/new` | checklists | 3 | set | h1b | body: Save anyway·Ws, Save*·P, Cancel·L, Remove·Ls, Add rule·Ps (5) | - | - | - | - | y |
| `checklist_lists/show` | checklists | 2 | both | h1b | - | - | - | - | table-resp | y |
| `checklists/confirm` | checklists | wizard | both | h1 | body: (submit)·W, Cancel·L (2) | - | - | - | - | y |
| `checklists/copy_form` | checklists | wizard | both | h1b | body+footer: (submit)·oPs, (submit)·P, Cancel·L (3) | - | - | - | filter, table | y |
| `checklists/edit` | checklists | 3 | set | h1b | body+menu+footer: Save anyway·Ws, Save*·P, new_checklist_chec·m, Remove·Ls, Add rule·Ps, Remove·Ls +4 (9; 2 row) | dd | - | x2 | - | y |
| `checklists/index` | checklists | 1 | both | h1b | body+footer: Search·P, New Checklist·G, (submit)·oP (3) | - | - | - | filter, bar | y |
| `checklists/new` | checklists | 3 | set | h1 | body: Save anyway·Ws, Save*·P (2) | - | - | - | - | y |
| `checklists/show` | checklists | 2 | both | h1b | footer+body: Edit·W, Take Snapshot·S, Recompute·oS, Copy·I, Restore·oSs, (submit)·oPs +1 (7; 2 row) | dd | Restore | - | filter, table-resp | y |
| `commitment_adjustments/new.html+count` | checklists-connectors | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitment_adjustments/new` | commitments | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitment_sources/edit.html+count` | checklists-connectors | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitment_sources/edit` | commitments | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitment_sources/new.html+count` | checklists-connectors | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitment_sources/new` | commitments | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitments/edit` | commitments | 3 | set | h1b | footer+body: Cancel·W, Save*·P, Add …·S, Add organizer·S (4; 1 row) | - | - | x2 | - | y |
| `commitments/index` | commitments | 1 | both | h1b | footer: New Commitment·G (1) | - | - | - | table | y |
| `commitments/new` | commitments | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `commitments/show` | commitments | 2 | both | h1b | footer+body: Set up·W, Add an adjustment·S, Print·S, Delete·D, Filter·S, Clear·L +1 (7; 1 row) | - | - | x3 | filter, table-resp | y |
| `devise/confirmations/new` | upstream* | sign-in | read | - | body+footer: Resend confirmatio·S, Sign Up·P, Sign in·P, Sign in with …·S (4) | - | - | - | - | n |
| `devise/mailer/confirmation_instructions` | upstream* | email | read | - | - | - | - | - | - | n |
| `devise/mailer/email_changed` | upstream* | email | read | - | - | - | - | - | - | n |
| `devise/mailer/password_change` | upstream* | email | read | - | - | - | - | - | - | n |
| `devise/mailer/reset_password_instructions` | upstream* | email | read | - | - | - | - | - | - | n |
| `devise/mailer/unlock_instructions` | upstream* | email | read | - | - | - | - | - | - | n |
| `devise/passwords/edit` | upstream | sign-in | read | - | footer: Change my password·P (1) | - | - | - | - | n |
| `devise/passwords/new` | upstream* | sign-in | read | - | body+footer: Send me reset pass·S, Sign Up·P, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+ (6) | - | - | - | - | n |
| `devise/registrations/edit` | upstream | sign-in | read | - | - | - | - | x2 | - | n |
| `devise/registrations/new` | upstream | sign-in | read | - | body+footer: Cancel·D, Sign up·P, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+ (6) | - | - | - | - | n |
| `devise/sessions/new` | upstream | sign-in | read | - | body+footer: Sign in·P, Sign Up·P, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+ (6) | - | - | - | - | n |
| `devise/unlocks/new` | upstream* | sign-in | read | - | body+footer: Resend unlock inst·S, Sign Up·P, Sign in·P, Sign in with …·S (4) | - | - | - | - | n |
| `doorkeeper/authorizations/error` | upstream | sign-in | read | h1 | - | - | - | - | - | n |
| `doorkeeper/authorizations/new` | upstream* | sign-in | read | - | body+footer: (submit)·P, (submit)·D, (submit)·L (3) | - | - | - | - | n |
| `doorkeeper/authorizations/show` | upstream | sign-in | read | h1 | - | - | - | - | - | n |
| `email_notices/show` | digests | 5 | set | h1 | footer: Save·P (1) | - | - | - | - | y |
| `event_types/edit` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `event_types/index` | upstream | 4 | set | h1 | footer: New Event Type·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `event_types/new` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `event_types/show` | upstream* | 4 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `events/arrange` | upstream* | 1 | both | h1b | body: Start Arranging·P, Print·K, Add New·P, (icon), Cancel·oS, Save·P (6) | - | - | - | - | y |
| `events/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `events/index` | upstream* | 1 | both | h1 | footer+body: New Event·G, Search·P, Clear Search·K, (submit)·oP (4) | dd | - | - | filter, bar | y |
| `events/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `events/print` | upstream* | print | both | h1 | body: Update·P, Arrange·I (2) | - | - | - | - | y |
| `events/show` | upstream* | 2 | both | h1sb | footer+body: Print·K, Arrange·I, Edit·W, Delete·D, New form for this ·Ss, Results·oPs +6 (12) | - | - | x1 | filter | y |
| `family/_ward_card` | my-gatherpack-family | section | read | -b | body: item.path, item.path, Activity·oS (3) | - | - | - | - | n |
| `family/show` | my-gatherpack-family | 2 | read | h1b | body: item.path, item.path, Activity·oS, item.path, See open shifts·oS (5) | - | - | - | - | y |
| `form_questions/edit` | forms | 3 | set | h1b | body: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `form_questions/new` | forms | 3 | set | h1b | body: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `form_responses/edit` | forms | 3 | read | h1s | footer+body: @submission.persis·W, Save*·S, Save*·P, based_on·Ds (4) | - | - | x1 | - | y |
| `form_responses/show` | forms | 2 | read | h1sb | footer+body: (submit)·P, Continue update·Ps, Discard update·oKs, Update answers·P, open.pending·P, Fill in·P +5 (11) | - | Withdraw response | x3 | - | y |
| `form_submissions/show` | forms | 2 | read | h1sb | footer: Back·W (1) | - | - | - | table | y |
| `forms/_event_panel` | forms | section | both | -sb | footer+body: New form for this ·Ss, Results·oPs, Tally·oPs, Printable list for·Ss, New form for this ·oSs (5) | - | - | - | - | n |
| `forms/audience` | forms | wizard | both | h1sb | footer: Back·W (1) | - | - | - | - | y |
| `forms/edit` | forms | 3 | set | h1sb | body+footer: Back·W, Save*·P, Save*·S, Save*·S, Save*·Ss, Save*·Ss +8 (14; 5 row) | - | - | x2 | table-resp | y |
| `forms/index` | forms | 1 | both | h1sb | footer: Printable list·S, New Form·P, Printable list·S (3) | - | - | - | table-resp | y |
| `forms/new` | forms | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `forms/preview` | forms | wizard | both | h1s | footer: Save*·P (1) | - | - | - | table | y |
| `forms/print_list` | forms | print | both | h1s | body: Show all·Ls, Show all·Ls, Show all·Ls, (submit)·P, Print·S (5) | - | - | - | filter, table-resp | y |
| `forms/reminder` | forms | 2 | both | h1s | footer+body: Use the default·Ls, Use the default·Ls, Save*·W, , name:·S, Cancel·oS (5) | - | - | - | - | y |
| `forms/results` | forms | 1 | both | h1sb | footer+body: (submit)·S, Back·W, Download CSV·P (3) | - | - | - | filter, table-resp | y |
| `forms/show` | forms | 2 | both | h1sb | footer+body: (submit)·S, All (…), Results·P, Tally·P, Printable list·P, Edit·S +7 (13) | - | Open/Close/Archive | x3 | filter, table-resp | y |
| `forms/tally` | forms | 1 | both | h1s | body+footer: Show all·Ls, (submit)·S, Back·W (3) | - | - | - | filter, table | y |
| `gateways/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `gateways/index` | upstream | 5 | set | - | body: i·P (1) | - | - | - | - | y |
| `gateways/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `gateways/show` | upstream* | 5 | set | h1 | footer: Edit·W, Delete·D, route·P (3) | - | - | x2 | - | y |
| `hooks/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `hooks/index` | upstream | 5 | set | h1 | footer: New Hook·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `hooks/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `hooks/show` | upstream* | 5 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `housekeeping/index` | housekeeping | 5 | set | h1 | body: (submit)·oP, Back to …·L, (submit)·Ls (3) | - | - | - | filter, table | n |
| `housekeeping/preview` | housekeeping | 5 | set | h1b | body: (submit)·P, Cancel·L (2) | - | - | - | table | n |
| `housekeeping_purges/show` | housekeeping | 5 | set | h1 | body: (submit)·D (1) | - | - | - | table | n |
| `intake/email_changes/done` | intake | public | read | h1 | body: Sign in·P (1) | - | - | - | - | n |
| `intake/email_changes/show` | intake | public | read | h1 | body: Use this email·P (1) | - | - | - | - | n |
| `intake/guardian_confirmations/show` | intake | public | read | h1 | body: I'm their guardian·P (1) | - | - | - | - | n |
| `intake/guardian_confirmations/sign_in` | intake | sign-in | read | h1 | body: Sign in·P (1) | - | - | - | - | n |
| `intake/join/busy` | intake | public | read | h1 | - | - | - | - | - | n |
| `intake/join/closed` | intake | public | read | h1 | - | - | - | - | - | n |
| `intake/join/show` | intake | public | read | h1 | body: Join·P, See what's next·L, Continue·P (3) | - | - | - | - | n |
| `intake/join/thanks` | intake | public | read | h1 | - | - | - | - | - | n |
| `intake/kiosk/show` | intake | kiosk | kiosk | h1 | body: Done·P+ (1) | - | - | - | - | n |
| `intake/kiosk/thanks` | intake | kiosk | kiosk | h1 | body: Next person·P+ (1) | - | - | - | - | n |
| `intake/mailer/approved` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/checklist_done` | intake-checklist | email | read | - | - | - | - | - | - | n |
| `intake/mailer/confirm_email_change` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/confirm_guardian` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/denied` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/digest` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/existing_account` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/finish_joining` | intake | email | read | - | - | - | - | - | - | n |
| `intake/mailer/registration_busy` | intake | email | read | - | - | - | - | - | - | n |
| `intake/me/show` | intake | public | read | h1sb | body+footer: Join·P, (submit)·Ps, Save·oP, Ask my guardian·oP, Add·oP (5) | - | - | x1 | - | n |
| `intake/registrations/edit` | intake | 3 | set | h1b | body: Save*·P, Cancel·oS (2) | - | - | - | - | n |
| `intake/registrations/index` | intake | 1 | set | h1sb | footer: Hide archived·oS, Show archived·oS, New Registration·G (3) | - | - | - | table | n |
| `intake/registrations/new` | intake | 3 | set | h1b | body: Save*·G (1) | - | - | - | - | n |
| `intake/registrations/show` | intake | 2 | set | h1sb | footer+body: Edit·P, Copy·oP, Waiting to finish·oP, Close now·W, Delete·D, (submit)·oD (6; 1 row) | - | Close now | x3 | table | n |
| `intake/registrations/waiting` | intake | 2 | set | h1sb | body+footer+header: Back to …·oS, Link·oPs, Keep separate·oSs, (submit)·oPs, (submit)·oPs, Send again·oSs +1 (7; 1 row) | - | - | x1 | table | n |
| `intake/spam_people/show` | intake | 5 | set | h1 | body: Delete·D, Cancel·oS (2) | - | - | - | - | n |
| `intake/verifications/expired` | intake | public | read | h1 | - | - | - | - | - | n |
| `intake/verifications/show` | intake | public | read | h1 | body: Finish·P, Confirm·P (2) | - | - | - | - | n |
| `intake/verifications/sign_in` | intake | sign-in | read | h1 | body: Sign in·P (1) | - | - | - | - | n |
| `inventory/imports/new` | inventory | 3 | set | h1 | body: (submit)·P (1) | - | - | - | - | y |
| `inventory/imports/preview` | inventory | wizard | set | h1 | footer: (submit)·P, Start again·S (2) | - | - | - | table-resp | y |
| `inventory/item_readings/edit` | inventory | 3 | set | h1 | body: Save readings·P, Cancel·W (2) | - | - | - | - | y |
| `inventory/item_sources/edit` | inventory | 3 | set | h1 | footer: Save*·P, Cancel·W, Remove·D (3) | - | - | x1 | - | y |
| `inventory/item_sources/new` | inventory | 3 | set | h1 | footer: Save*·P, Cancel·W (2) | - | - | - | - | y |
| `inventory/items/edit` | inventory | 3 | set | h1 | body: Save*·P (1) | - | - | - | - | y |
| `inventory/items/index` | inventory | 1 | both | h1b | footer: Import·S, New item·G, Search·P, Clear Search·K, send·S, inventory_setup_pa·S (6) | - | - | - | filter, table-resp | y |
| `inventory/items/new` | inventory | 3 | set | h1 | body: Save*·P (1) | - | - | - | - | y |
| `inventory/items/show` | inventory | 2 | both | h1b | footer+body: Undo·K, Edit·W, Label·S, Delete·D, Add where to buy·S, inventory_kind_lab·P +1 (7; 1 row) | - | - | x1 | - | y |
| `inventory/labels/show` | inventory | print | set | h1 | footer: Print·P (1) | - | - | - | - | y |
| `inventory/locations/count` | inventory | wizard | set | h1 | body: −·S, +·S, Back·S, Next·P, Save counts·P+ (5) | - | - | - | - | y |
| `inventory/locations/edit` | inventory | 3 | set | h1 | body: Save*·P (1) | - | - | - | - | y |
| `inventory/locations/index` | inventory | 1 | set | h1b | footer+header: New place·G, (submit)·P, send·S, inventory_setup_pa·S (4) | - | - | - | filter | y |
| `inventory/locations/new` | inventory | 3 | set | h1 | body: Save*·P (1) | - | - | - | - | y |
| `inventory/locations/show` | inventory | 2 | set | h1b | footer+body: Undo·K, Edit·W, Add a place inside·S, Add an item here·S, Label·S, Delete·D +4 (10) | - | - | x1 | - | y |
| `inventory/machines/index` | inventory | 1 | set | h1b | - | - | - | - | - | y |
| `inventory/machines/show` | inventory | 2 | set | h1b | footer: Install·P+ (1) | - | - | - | - | y |
| `inventory/movements/index` | inventory | 1 | set | h1b | footer: (submit)·P, Clear·K, Print·K, Download CSV·S, Print·P, Undo·oSs +2 (8) | - | - | - | filter | y |
| `inventory/movements/new` | inventory | 3 | set | h1 | body: −·S, +·S, Cancel·W+, words·P+ (4) | - | - | - | - | y |
| `inventory/reorder/index` | inventory | 1 | set | h1b | footer+body: (submit)·P, , name:·P, send·S, inventory_setup_pa·S (4) | - | - | - | filter, table-resp | y |
| `inventory/reorder/print` | inventory | print | set | h1 | footer: Print·P, Back to the list·S (2) | - | - | - | table | y |
| `inventory/search/index` | inventory | 1 | both | -b | footer+body: Undo·K, (icon)·P, inventory_location·S, inventory_machine_·S, send·S, inventory_setup_pa·S (6) | - | - | - | filter | y |
| `inventory/setup/show` | inventory | 4 | set | h1b | body+footer: Save·G+, Save·G+, Add a row·S, (submit)·G+, list.plural_label·S (5) | - | - | - | - | y |
| `inventory/units/check` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `inventory/units/edit` | inventory | 3 | set | h1 | body: Save*·P+, Cancel·W+ (2) | - | - | - | - | y |
| `inventory/units/index` | inventory | 1 | set | h1b | footer: Find·P+ (1) | - | - | - | filter | y |
| `inventory/units/install` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `inventory/units/mark_for_repair` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `inventory/units/move` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `inventory/units/new` | inventory | 3 | set | h1 | body: Add units·P+ (1) | - | - | - | - | y |
| `inventory/units/repaired` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `inventory/units/retire` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `inventory/units/show` | inventory | 2 | set | h1b | footer+body: Undo·oSs, Edit code and deta·W (2) | - | - | - | table-resp | y |
| `inventory/units/take_off` | inventory | wizard | set | h1b | footer: Cancel·W+, submit (2) | - | - | - | - | y |
| `layouts/application` | upstream* | layout | set | - | body: (icon), (icon), Cancel·S, Delete·D (4) | - | - | - | - | y |
| `layouts/devise` | upstream* | layout | set | - | - | - | - | - | - | n |
| `layouts/doorkeeper/application` | upstream | layout | set | - | body: (icon) (1) | - | - | - | - | n |
| `layouts/intake_kiosk` | intake | layout | set | - | - | - | - | - | - | n |
| `layouts/intake_public` | intake | layout | set | - | - | - | - | - | - | n |
| `layouts/kiosk` | upstream* | layout | set | - | footer: Stop Impersonating·Ds, Sign out·oLts (2) | - | Stop Impersonating | - | - | n |
| `layouts/mailer` | upstream | email | read | - | - | - | - | - | - | n |
| `layouts/mailer.text` | upstream | email | read | - | - | - | - | - | - | n |
| `layouts/theme_preview` | theme-palette | layout | set | - | - | - | - | - | - | n |
| `ledger_entries/_ledger_entry_card` | upstream | section | set | h1b | footer+body: Unsplit·K, Split·K, Edit·W, Delete·D (4) | - | - | x1 | - | n |
| `ledger_entries/edit` | upstream | 3 | set | h1b | footer: Split Again·K, Cancel·W, Save*·P (3) | - | - | - | - | y |
| `ledger_entries/new` | upstream | 3 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledger_entries/show` | upstream* | 2 | set | h1b | footer+body: Unsplit·K, Split·K, Edit·W, Delete·D, Unsplit·K, Split·K +6 (12) | - | - | x3 | - | y |
| `ledger_entry_links/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledger_entry_links/index` | upstream | 1 | set | h1 | footer: New Ledger Entry L·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `ledger_entry_links/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledger_entry_links/show` | upstream* | 2 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `ledger_ownerships/index` | upstream | 1 | set | h1 | footer: New Ledger Ownersh·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `ledger_ownerships/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledger_ownerships/show` | upstream | 2 | set | h1 | footer: Delete·D (1) | - | - | x1 | - | y |
| `ledger_payments/new` | upstream | 3 | set | h1 | body: Save*·P+ (1) | - | - | - | - | n |
| `ledger_tags/edit` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledger_tags/index` | upstream | 4 | set | h1 | footer: New Ledger Tag·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `ledger_tags/new` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledger_tags/show` | upstream | 4 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `ledger_transfers/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledgers/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledgers/index` | upstream | 1 | set | h1 | footer: New Ledger·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `ledgers/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `ledgers/show` | upstream* | 2 | set | h1b | footer+body: Transfer·P, Post New Entry·P, Pay Into Ledger·P, Manage Ownership·W, Edit·W, Delete·D +5 (11) | - | - | x2 | - | y |
| `mailbox_messages/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `mailbox_messages/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `mailbox_messages/show` | upstream* | 5 | set | h1 | footer: Delete·D (1) | - | - | x1 | - | y |
| `mailboxes/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `mailboxes/index` | upstream | 5 | set | h1 | footer: New Mailbox·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `mailboxes/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `mailboxes/show` | upstream | 5 | set | h1b | footer: New Message·G, Search Messages·P, Clear Search·K, Edit·W, Delete·D (5) | dd | - | x1 | filter | y |
| `managed_lists/edit` | managed-lists | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `managed_lists/index` | managed-lists | 4 | set | h1s | footer: New …·G, move_managed_list_·oSs, move_managed_list_·oSs, Edit·oWs, Retire·oSs, Restore·oSs +9 (15) | - | Retire/Restore | x2 | - | y |
| `managed_lists/merge` | managed-lists | 4 | set | h1 | footer: Cancel·W, Merge·D (2) | - | - | - | - | y |
| `managed_lists/new` | managed-lists | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `mcp/calls/index` | mcp | 5 | set | h1s | footer: Search·P, Clear Search·K (2) | - | - | - | filter, table-resp | n |
| `mcp/page_renders/show` | mcp | 5 | set | - | - | - | - | - | - | n |
| `membership_applications/index` | upstream* | 1 | set | -sb | footer+body: (submit)·Gs, (submit)·oDs, Delete as spam·oDs, View Details·oPs, Approve·Gs, Deny·Ds +2 (8) | - | Approve/Withdraw | x1 | purges | y |
| `membership_applications/show` | upstream | 2 | set | h1b | footer+body: Approve·G, Deny·D, Withdraw Applicati·oS (3) | - | Approve/Withdraw Application | x1 | - | y |
| `memberships/_card` | upstream | section | both | - | body: membership.manager·Ws, Remove·Ds (2) | - | - | x1 | - | n |
| `memberships/by_person` | upstream* | 1 | both | h1b | body: Delete·D (1) | - | - | x1 | add_candidates | y |
| `memberships/by_team` | upstream* | 1 | both | -b | body+footer: , name: nil, form:·oP, (submit)·oP, Clear … older than·oDs, (icon)·P, Search·P, Clear Search·K (6) | - | - | - | filter, people_bar, purges, add_candidates | y |
| `memberships/candidates` | search-and-add | misc | both | - | - | - | - | - | add_candidates | n |
| `memberships/create.turbo_stream` | search-and-add | stream | both | - | - | - | - | - | - | n |
| `memberships/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `memberships/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `memberships/show` | upstream | 2 | both | h1b | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `my_gatherpack/activity/show` | my-gatherpack-activity | 2 | read | h1b | body: Show·P, section.name·oSs (2) | - | - | - | filter | y |
| `notification_settings/show` | phone-notifications | 2 | read | h1 | body: Send a test notifi·oS (1; 1 row) | - | - | - | - | y |
| `oauth_applications/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `oauth_applications/index` | upstream* | 5 | set | h1 | footer: New OAuth Applicat·G, Search·P, Clear Search·K (3; 2 row) | - | - | x1 | filter, table-resp | y |
| `oauth_applications/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `oauth_applications/show` | upstream* | 5 | set | h1 | body+footer: " data-action="cli·Ss, " data-action="cli·Ss, Regenerate·Ws, Edit·W, Delete·D, Back to OAuth Appl·K (6) | - | - | x2 | - | y |
| `order_inventory/reorder_drafts/new` | order-inventory | 3 | set | h1s | body: (submit)·P (1) | - | - | - | - | n |
| `orders/approval_steps/edit` | orders | 4 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `orders/approval_steps/index` | orders | 4 | set | h1s | footer: New Approval Step·G, move_orders_approv·oSs, move_orders_approv·oSs, Edit·oWs, Retire·oSs, Restore·oSs +5 (11) | - | Retire/Restore | - | - | y |
| `orders/approval_steps/new` | orders | 4 | set | h1b | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `orders/approvals/index` | orders | 1 | set | h1sb | - | - | - | - | - | y |
| `orders/deliveries/index` | orders | 1 | set | h1s | header: Show all I can rec·S+, Only mine·S+ (2) | - | - | - | - | y |
| `orders/deliveries/new` | orders | 3 | set | h1s | footer: Record delivery·P+, Cancel·W+ (2) | - | - | - | - | y |
| `orders/funding_source_budgets/edit` | orders | 4 | set | h1s | body: Save·P (1) | - | - | - | - | y |
| `orders/funding_sources/edit` | orders | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `orders/funding_sources/index` | orders | 4 | set | h1sb | header: New funding source·G (1) | - | - | - | table-resp | y |
| `orders/funding_sources/new` | orders | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `orders/funding_sources/report` | orders | 4 | set | h1 | body: Download CSV·S (1) | - | - | - | table-resp | y |
| `orders/funding_sources/show` | orders | 4 | set | h1 | header: Report·S, Edit·W, Delete·D (3) | - | - | - | - | y |
| `orders/purchases/edit` | orders | 3 | set | h1 | footer: Save*·P, Cancel·W (2) | - | - | - | - | y |
| `orders/purchases/index` | orders | 1 | set | h1sb | footer+header: All orders·S, Orders I placed·S, To buy·P, All orders·S, Not in ledger·S (5) | - | - | - | - | y |
| `orders/purchases/new` | orders | 3 | set | h1s | footer: Save*·P, Back to To buy·S (2) | - | - | - | table-resp | y |
| `orders/purchases/show` | orders | 2 | set | h1sb | body+footer: Edit·W, (submit)·P, Mark delayed·W, Change quantity·S, Split·S, Cancel item·D (6) | - | - | - | table-resp | y |
| `orders/purchases/to_buy` | orders | 1 | set | h1sb | body+footer: Orders placed·S, Mark delayed·W, Change quantity·S, Split·S, Cancel item·D, (submit)·P (6) | - | - | - | filter, table-resp | y |
| `orders/reports/index` | orders | 1 | set | h1s | - | - | - | - | - | y |
| `orders/reports/show` | orders | 2 | set | h1s | body: Download CSV·S (1) | - | - | - | table-resp | y |
| `orders/requests/edit` | orders | 3 | set | h1sb | body: Remove·L, Remove·L, (icon)·S, Submit for approva·P, Save·S, Send back for appr·P +1 (7) | - | - | - | - | y |
| `orders/requests/index` | orders | 1 | both | h1sb | body: New request·P (1) | - | - | - | tabs | y |
| `orders/requests/new` | orders | 3 | set | h1s | body: Remove·L, Remove·L, (icon)·S, Submit for approva·P, Save·S, Send back for appr·P +1 (7) | - | - | - | - | y |
| `orders/requests/show` | orders | 2 | both | h1sb | body+footer: Finish request·P, Update·P, Change·W, Delete draft·D, Cancel request·D, Order again·S +17 (23) | - | Cancel request/Stop following/Approve/Open To buy | x2 | table-resp | y |
| `orders/settings/show` | orders | 4 | set | h1sb | body+footer: Add a row·S, Add a row·S, Add a row·S, Add a row·S, Save·G+, Cancel·P+ (6) | - | - | - | - | y |
| `orders/vendors/edit` | orders | 4 | set | h1 | footer+body: Cancel·W, Save*·P, Test·S (3) | - | - | - | filter | y |
| `orders/vendors/index` | orders | 4 | set | h1sb | header: New vendor·G (1) | - | - | - | table-resp | y |
| `orders/vendors/new` | orders | 4 | set | h1 | footer+body: Cancel·W, Save*·P, Test·S (3) | - | - | - | filter | y |
| `orders/vendors/pattern_test` | orders | 4 | set | - | - | - | - | - | - | n |
| `orders/vendors/show` | orders | 4 | set | h1 | header: Edit·W, Delete·D (2) | - | - | - | - | y |
| `pages/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `pages/index` | upstream | 1 | read | h1 | footer: New Page·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `pages/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `pages/show` | upstream | 2 | read | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `people/_show_shared` | upstream* | section | both | - | - | - | - | - | - | y |
| `people/calendar` | upstream | 1 | both | h1 | - | - | - | - | - | y |
| `people/edit` | upstream | 3 | set | h1 | body+footer: Change Email/Passw·P, Create Email/Passw·P, Cancel·W, Save*·P (4) | - | - | - | - | y |
| `people/index` | upstream* | 1 | both | h1 | footer+body: New Person·G, Search·P, Clear Search·K, , name: nil, form:·oP, (submit)·oP, Clear … older than·oDs (6) | dd | - | - | filter, people_bar, purges | y |
| `people/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `people/recent_activity` | upstream | 1 | both | h1b | - | - | - | - | - | y |
| `people/relationships` | upstream* | 1 | both | h1s | body+footer: Reverse·W, Delete·D, Add Relationship·I (3) | - | - | x3 | - | y |
| `people/show` | upstream* | 2 | both | h1sb | footer: Impersonate·K, Edit Profile·W, Change Email/Passw·P, Create Email/Passw·P, Email notices·S, Delete·D (6) | - | - | x1 | - | y |
| `people/statistics` | upstream* | 1 | both | h1b | - | - | - | - | - | y |
| `person_checklists/show` | checklists | 2 | read | h1b | - | - | - | - | - | y |
| `person_commitments/show` | commitments | 2 | read | h1b | - | - | - | - | - | y |
| `person_field_groups/edit` | person-fields | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `person_field_groups/index` | person-fields | 4 | set | h1s | footer: New Section·G, Person Fields·S (2; 3 row) | - | - | x1 | table | y |
| `person_field_groups/new` | person-fields | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `person_fields/edit` | person-fields | 4 | set | h1sb | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `person_fields/index` | person-fields | 4 | set | h1sb | footer: New Field·G, Preview as…·P, Apply recommended ·I, Sections·S, Hide archived·K, Show archived·K (6; 5 row) | - | Restore/Archive | x2 | table-resp | y |
| `person_fields/new` | person-fields | 4 | set | h1sb | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `person_fields/preview` | person-fields | 4 | set | h1s | footer: Save*·P (1) | - | - | - | table | y |
| `person_fields/show` | person-fields | 4 | set | h1b | footer: Edit·W, Back·S (2) | - | - | - | - | y |
| `person_forms/show` | forms | 2 | read | h1sb | body: Sign·Ps, label·Ps, Sign·Ps, label·Ps (4) | - | - | - | - | y |
| `person_merges/new` | person-merge | 5 | set | h1s | footer: Cancel·W, Save*·P, Save*·D (3) | - | - | x1 | table | y |
| `push_keys/edit` | phone-notifications | 5 | set | h1 | footer: Cancel·W, Replace keys·D (2) | - | - | - | - | y |
| `pwa/manifest.json` | upstream* | pwa | set | - | - | - | - | - | - | n |
| `pwa/service-worker.js` | installable-app | pwa | set | - | - | - | - | - | - | n |
| `questions/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `questions/index` | upstream* | 1 | read | h1sb | footer: New Question·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `questions/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `questions/show` | upstream* | 2 | read | h1sb | footer+body: ">, reply-form#toggle"·Ls, Edit·Ls, Delete·Ls, Save*·Ps, "> +23 (29) | - | Reopen/Close | x5 | - | y |
| `relationship_types/edit` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `relationship_types/index` | upstream | 4 | set | h1 | footer: New Relationship T·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `relationship_types/new` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `relationship_types/show` | upstream* | 4 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | table-resp | y |
| `relationships/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `replies/edit` | upstream | 3 | set | - | footer: Save*·P, Cancel·S (2) | - | - | - | - | y |
| `reports/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `reports/index` | upstream | 5 | set | h1 | footer: New Report·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `reports/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `reports/run` | upstream* | 5 | set | h1 | footer: Show Code·I, Run·G, Edit·W, Delete·D (4) | - | - | x1 | - | y |
| `reports/show` | upstream* | 5 | set | h1 | footer: Run·G, Edit·W, Delete·D (3) | - | - | x1 | - | y |
| `roster_signups/edit` | signups | 3 | set | h1 | body: Back to the roster·W, Save*·P, Save*·S (3) | - | - | - | - | y |
| `roster_signups/new` | signups | 3 | set | h1 | body: Choose·S, Cancel·W, Save*·P (3) | - | - | - | filter | y |
| `search/combo.turbo_stream` | upstream | stream | read | - | - | - | - | - | - | n |
| `search/index` | upstream | 1 | read | - | - | - | - | - | - | y |
| `settings/index` | upstream* | 5 | set | h1 | footer: page.label·P, Save·G+, Cancel·P+ (3) | - | - | - | - | y |
| `share/show` | installable-app | 2 | read | h1 | body: action.label·P+ (1) | - | - | - | - | n |
| `shortcuts/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `shortcuts/index` | upstream | 5 | set | h1 | footer: New Shortcut·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `shortcuts/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `shortcuts/show` | upstream* | 5 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `signup_checklists/_sheet_panel` | checklists-connectors | section | set | -b | - | - | - | - | - | n |
| `signup_messages/new` | signups | 3 | set | h1 | footer: Cancel·W, Send·P (2) | - | - | - | - | y |
| `signup_positions/edit` | signups | 3 | set | h1b | footer: Back to the sheet·W, Save*·P, Save*·Ss, Remove·oDs (4) | - | - | - | - | y |
| `signup_positions/new` | signups | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `signup_sheet_events/edit` | signups | 3 | set | h1 | footer: Cancel·W, Save·P (2) | - | - | - | - | y |
| `signup_sheet_events/new` | signups | 3 | set | h1 | body+footer: More rows·oSs, Cancel·W, Add these dates·P, Filter·S, Clear·L, Add ticked events·P (6) | - | - | - | filter | y |
| `signup_sheets/_event_panel` | signups | section | both | -b | footer: Sign up·Ps (1) | - | - | - | - | n |
| `signup_sheets/edit` | signups | 3 | set | h1b | body+footer+header: Roster·Is, Cancel·W, Save*·P, Edit and rules·Ws, Add a position·G, Add dates·G +5 (11; 1 row) | - | - | x4 | - | y |
| `signup_sheets/index` | signups | 1 | both | h1b | footer: New Sign-up Sheet·G (1; 1 row) | - | - | - | table | y |
| `signup_sheets/new` | signups | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `signup_sheets/roster` | signups | 1 | both | h1b | header+body: Add a sign-up·G, Message·P, Print·S, Set up·W, Filter·S, Clear·L +1 (7; 1 row) | - | - | x2 | filter, table-resp | y |
| `signup_sheets/show` | signups | 2 | both | h1b | body+footer: Set up·W, Roster·I, policy·D, Change·Ps, Cancel·Ds, Change·Ps +2 (8) | - | - | x3 | - | y |
| `signup_slots/index` | signups | 1 | set | h1 | footer: Back to the sheet·W, Save·P (2) | - | - | - | table-resp | y |
| `signups/edit` | signups | 3 | read | h1 | footer: Back·S, Save*·P (2) | - | - | - | - | y |
| `signups/new` | signups | 3 | read | h1 | footer: Back·S, Save*·P (2) | - | - | - | - | y |
| `signups/new.turbo_stream` | signups | stream | read | - | - | - | - | - | - | n |
| `team_moves/new` | housekeeping | 3 | set | -b | footer+body: (submit)·oP, (submit)·P, Cancel·L (3) | - | - | - | filter, table | y |
| `team_moves/preview` | housekeeping | wizard | set | -b | body: (submit)·P, Cancel·L (2) | - | - | - | - | y |
| `team_types/edit` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `team_types/index` | upstream | 4 | set | h1 | footer: New Team Type·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `team_types/new` | upstream | 4 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `team_types/show` | upstream | 4 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `teams/_show_shared` | upstream* | section | both | -b | - | - | - | - | - | y |
| `teams/applications` | upstream* | 1 | both | -sb | footer+body: Link·oPs, Keep separate·oSs, (submit)·oPs, (submit)·oPs, Send again·oSs, (submit)·oPs +6 (12) | - | Approve | x3 | - | y |
| `teams/badges` | upstream | 1 | both | h1b | - | - | - | - | - | y |
| `teams/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `teams/events` | upstream | 1 | both | h1b | - | - | - | - | - | y |
| `teams/index` | upstream | 1 | both | h1 | footer: New Team·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `teams/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `teams/pages` | upstream | 1 | both | h1b | - | - | - | - | - | y |
| `teams/show` | upstream* | 2 | both | h1sb | body+footer+header: View All·oPs, (icon), team_memberships_p·G, (icon)·I, Edit·W, Delete·D +3 (9) | - | - | x1 | - | y |
| `teams/show_public` | upstream* | 2 | both | h1sb | body+footer: team_memberships_p·G, (icon)·I, (icon), Cancel·S, Submit Application·I (5) | - | - | - | - | y |
| `theme/edit` | upstream* | 5 | set | -s | body+footer: Preview the new lo·oP, Use these as my st·oPs, Reset to defaults·oS, (icon)·oSs, Save Theme·G+, Cancel·P+ +5 (11) | - | Close | - | table-resp | y |
| `theme/show` | upstream* | 5 | set | h1sb | footer: Edit Theme·P+ (1) | - | - | - | - | y |
| `theme_previews/show` | theme-palette | 5 | set | h1sb | body: Primary·P, Outline·oP, Secondary·oS (3) | - | - | - | table | n |
| `time_clock_periods/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `time_clock_periods/index` | upstream | 1 | both | h1 | footer: New Time Clock Per·G, Time Clock Punches·I, Search·P, Clear Search·K (4) | dd | - | - | filter | y |
| `time_clock_periods/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `time_clock_periods/show` | upstream | 2 | both | h1 | footer: Back to Time Clock·G, Period Summary·I, Edit·W, Delete·D, Search·P, Clear Search·K (6) | dd | - | x1 | filter, table-resp | y |
| `time_clock_periods/summary` | upstream | 1 | both | h1s | body: Filter·P, Clear·S (2) | - | - | - | filter | y |
| `time_clock_punches/edit` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P, Delete·Ds (3) | - | - | x1 | - | y |
| `time_clock_punches/flagged` | upstream* | 1 | both | h1sb | footer: Back to Time Clock·S, Save·Ss (2; 6 row) | - | - | x6 | table-resp | y |
| `time_clock_punches/index` | upstream* | 1 | both | h1 | footer: New Time Clock Pun·G, Time Clock Periods·I, Flag Review·W, Search·P, Clear Search·K, Time Clock Kiosk·W (6) | dd | - | - | filter, table-resp | y |
| `time_clock_punches/new` | upstream | 3 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `time_kiosk/index` | upstream | kiosk | kiosk | - | body: Save*·P+, (icon) (2) | - | - | - | - | n |
| `time_kiosk/refused` | security-series | kiosk | kiosk | - | body: Sign out·S (1) | - | - | - | - | n |
| `tokens/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `tokens/index` | upstream | 5 | set | h1 | footer: New Token·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `tokens/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `tokens/show` | upstream | 5 | set | h1 | footer: Edit·W, Delete·D, Back to Tokens·K (3) | - | - | x1 | - | y |
| `users/edit` | upstream* | 5 | set | h1 | footer: Cancel·W, Save*·P, Authorized Applica·S (3) | - | - | - | - | y |
| `users/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `variables/edit` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `variables/index` | upstream | 5 | set | h1 | footer: New Variable·G, Search·P, Clear Search·K (3) | dd | - | - | filter | y |
| `variables/new` | upstream | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `variables/show` | upstream | 5 | set | h1 | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `welcome/dashboard` | upstream* | dashboard | read | -sb | header: New request·P (1) | - | - | - | - | y |
| `welcome/setup` | upstream | 4 | set | -s | body: item.label·P+, Settings·P+, Theme·P+, Gateways·P+ (4) | - | - | - | - | y |
| `widgets/_card` | widgets | section | set | - | - | - | - | - | - | n |
| `widgets/body` | widgets | 5 | set | - | - | - | - | - | - | n |
| `widgets/edit` | widgets | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `widgets/index` | widgets | 5 | set | h1s | footer: New Widget·G (1) | - | - | - | table | y |
| `widgets/new` | widgets | 5 | set | h1 | footer: Cancel·W, Save*·P (2) | - | - | - | - | y |
| `widgets/show` | widgets | 5 | set | h1s | footer: Edit·W, Delete·D (2) | - | - | x1 | - | y |
| `devise/sessions/new.html.erb [modern_skin override]` | modern-skin (override) | sign-in | read | - | body+footer: Sign in·P, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+, omniauth_authorize·S+ (5) | - | - | - | - | n |
| `layouts/devise.html.erb [modern_skin override]` | modern-skin (override) | layout | set | - | - | - | - | - | - | n |
| `time_clock_punches/index.html.erb [my_gatherpack override]` | my-gatherpack (override) | 1 | both | h1 | footer: New Time Clock Pun·G, Time Clock Periods·I, Flag Review·W, Search·P, Clear Search·K, Time Clock Kiosk·W (6) | dd | - | - | filter, table-resp | y |
| `welcome/dashboard.html.erb [my_gatherpack override]` | my-gatherpack (override) | dashboard | read | h1 | - | - | - | - | - | y |
