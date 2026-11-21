# BL-061: Audit every screen and standardize them

| | |
|---|---|
| Kind | fork-only (design) |
| Priority | high |
| Status | done: standard in `fork-spec` "Screen design" and gp-map "Views"; plan and inventory in [`screen-standard-spec`](../specs/screen-standard-spec.md); fix-ups BL-062 to BL-073 |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | none for the audit itself (docs only); the fix-up work it plans gets its own items and branches |
| Upstream issue / PR | none |

## Summary

Each feature arranges its screens its own way: where the buttons are, what they're called and coloured, whether a state change is a button or a setting, where its configuration lives. Someone who has learned Forms has to learn Checklists, Orders and Sign-ups from scratch. Audit every screen in the integration build against the two principles in the `fork-spec` skill (**Consistency** and **Simple first**, "Screen design"), write one standard for each kind of screen, and plan the work that brings every feature to it. Going one layer deeper in any feature (list, then a record, then its edit page, then the feature's setup) should feel the same everywhere.

## Evidence

Counts at `hbr/integration` `c4700b175` (upstream plus every fork feature):

- 99 view folders, 382 page templates, 693 templates with partials.
- Action rows are built at least three ways: `card-footer` (219 files), a `.actions` div (7), a closing `d-flex gap-2` row (37).
- 32 files use a dropdown for extra actions; most pages put every action in one flat row instead (`forms/show.html.erb:63-90` has up to eleven).
- Button styles: `btn-primary` 270, `btn-warning` 179, `btn-sm` 162, `btn-secondary` 132, `btn-danger` 67, `btn-success` 60, `btn-dark` 54, `btn-link` 30, `btn-outline-*` 37+. "Edit" alone appears as `btn-warning` (39), `btn-sm` row buttons (10), `btn-primary`, `btn-secondary` and `btn-link`. The convention in gp-map "Views" (Edit `btn-warning`, Cancel `btn-warning`, Print `btn-dark`, …) is upstream's and is itself hard to read: Edit and Cancel share a colour.
- State changes are buttons with unclear words: Forms' Open/Close (fixed by [BL-060](BL-060-one-form-results-page.md)); look for the same pattern elsewhere (publish, activate, approve, archive).
- Tabs on a record page exist in three places only (`people/_show_shared`, `teams/_show_shared`, `forms/edit`); other features with many parts use separate pages or long single pages.
- 84 files confirm with a browser `turbo_confirm` dialog; the `fork-spec` rule is "warnings sit by the action".

## What it does

### 1. Inventory

One row per page template in the integration build (partials only where they render a whole section, like an event panel or a profile tab). Columns:

- Feature and owner (upstream, or the fork branch from `FORK.md`).
- **Layer**: 1 list/index, 2 record page, 3 edit/new form, 4 feature setup (types, settings, the Setup page section), 5 site settings, or other (print, kiosk, wizard, dashboard widget, My GatherPack card, email).
- **Audience**: people only reading (members, guardians, report readers) or people setting up (leaders, admins).
- Header (title, summary line, state shown in words or as a badge).
- Where actions sit (header, footer, inline, row) and which ones, in order, with their button style.
- Extra actions: flat or in a More menu.
- State changes: button, setting, or both; whether the label says the effect.
- Confirmations: browser dialog or inline question by Save.
- Configuration found on a reading screen (filters fine; settings not).
- Filters and tables: which shared partial, if any.
- Screenshot reference.

Collect it from the code (views, controller actions, policies) and look at each screen in the installed Chrome against the desktop dev database (Northwind) or demo.hbrlive.com; take a phone-width look too. Signed in as an admin, a leader, a member and a guardian, so each audience's view is recorded. The inventory is a working table, kept in `fork/specs/screen-standard-spec.md` (appendix) and deleted once the fix-up work ships.

### 2. The standard

From the inventory, write one standard per screen kind, layer 1 to 5 plus the "other" kinds that recur. Each says, with a sketch:

- The page shape: header card (title, one-line summary, current state in words), then filters, then content, then the action row.
- Where actions go and in what order: one primary action, at most three visible, the rest in a **More** menu; destructive actions last, in More.
- Button words and styles: one word per action across the app (Edit, Remind, Print, Download CSV, Archive, Delete, Save, Cancel) and one style each. Replace the Edit/Cancel `btn-warning` clash: decide new styles once, apply them to fork screens, and decide upstream screens under section 4.
- State changes (open/closed, active/retired, published, approved) are a labelled choice on the setup page that says its effect, with the state shown in words on the record page.
- Confirmations: the inline "question above Save" pattern; browser dialogs only where there's no form to put it in (decide which).
- Configuration: where each layer's settings live (record settings on its Edit page; vocabulary tables and feature-wide settings on the feature's section of the main Setup page, as upstream's types are; site settings in admin). Reading screens carry filters only.
- Navigation between layers: breadcrumbs everywhere, one way back, a record's parts as tabs when it has more than two (as `people/_show_shared` does), never a separate unlinked page.
- Phone width: what collapses into More and how tables scroll.

The standard goes into the `fork-spec` skill "Screen design" (the rules) and gp-map "Views" (the button table, replacing the current convention paragraph). Each rule lives in one of those two places, not both. Shared partials for the repeated parts (action row with More menu, state line, inline confirm, filter bar, people table) are listed with their names so feature work can use them.

### 3. The plan

`fork/specs/screen-standard-spec.md` holds the standard's reasoning, the inventory appendix and the plan:

- Shared partials first, on their own branch, since every fix-up depends on them.
- Then one backlog item per feature (or per group of small features), each listing its screens, what changes, and tests. Ordered by how many reading-audience people use the screens: Home/My GatherPack, Forms, Sign-ups, Checklists, Events, People and Teams profiles, then the setup-only features.
- Each fork feature's changes go on its own `feature/*` branch, behind no new flag (they rearrange the feature's own screens). A change that makes a screen work differently for users (a button moved into setup, as in BL-060) is called out in the item and the changelog.
- BL-060 is the first worked example; the audit checks it against the final standard.

### 4. Upstream screens

Upstream's own screens (People, Teams, Events, Badges, Settings) are part of the inventory, because consistency is judged across the whole app. For each difference, the plan records one of:

- **Fork matches upstream**: the fork's screens follow upstream's pattern here; no upstream change.
- **Fork wrapper**: change the look through a fork partial, helper or CSS without editing the upstream view.
- **Upstream edit**: only where nothing else works; listed with its `FORK.md` "Upstream files touched" cost, for Corey to approve case by case.

Whether any of it is offered to upstream is Corey's call per change; the plan doesn't assume it.

## Done when

- Every page template in the integration build has an inventory row.
- The standard is in `fork-spec` and gp-map "Views", and the old button paragraph is replaced.
- The shared partials and every fix-up item exist in the backlog, ordered, each detailed enough to pick up cold.
- `bin/fork-doc-lint` passes.

## Fork notes

- Docs-only: no code changes in this item. The reviewer agent already checks screens against "Screen design", so new work follows the standard as soon as it's written.
- Help site (gphelp) screenshots will need retaking feature by feature as fix-ups ship; each fix-up item says which.
- No real names in screenshots kept in the repo: Northwind data only.
