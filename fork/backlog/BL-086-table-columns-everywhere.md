# BL-086: Reading tables without Columns or heading sort/filter

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | not started |
| Added | 2026-11-25 |
| Commit checked | `hbr/integration` @ `d986f7e19` (`v0.0.0-hbr.54`) |
| Planned branches | `feature/forms`, `feature/person-fields`, `feature/widgets`, `feature/kiosk-devices`, `feature/inventory`, `feature/orders`, `feature/security-series` |
| Upstream issue / PR | none |

## Summary

The screen standard (fork-spec "Tables") says every table people read gets **Columns** and sorting and filtering in its headings, with no exceptions for small or admin-only screens. These fork screens predate that rule and have neither. Accounting's tables are fixed separately on `feature/accounting` (task 403).

## Evidence

Found by listing views with a `<table>` or `shared/_people_table` and no `column_chooser_data` / `choose_columns:` at `d986f7e19`:

| Screen | View | Branch |
|---|---|---|
| Form page (answers table) | `app/views/forms/show.html.erb` | `feature/forms` |
| Form totals | `app/views/forms/_totals.html.erb` | `feature/forms` (check `feature/forms-auto-reminders`, which also has it) |
| One submission | `app/views/form_submissions/show.html.erb` | `feature/forms` |
| A person's form | `app/views/person_forms/show.html.erb` | `feature/forms` |
| Person fields list | `app/views/person_fields/index.html.erb` | `feature/person-fields` |
| Field groups list | `app/views/person_field_groups/index.html.erb` | `feature/person-fields` |
| Widgets list | `app/views/widgets/index.html.erb` | `feature/widgets` |
| Kiosk devices list | `app/views/kiosk_devices/index.html.erb` | `feature/kiosk-devices` |
| Inventory unit page | `app/views/inventory/units/show.html.erb` | `feature/inventory` |
| An order's purchase table | `app/views/orders/requests/_purchase.html.erb` | `feature/orders` |
| Authorized apps list | `app/views/authorized_applications/index.html.erb` | `feature/security-series` ("let members revoke apps") |

Confirm each file's owning branch in `FORK.md` before editing: the branch column is from the worktrees, not checked against the manifest.

Left out on purpose:
- Edit-form tables (`forms/_edit_questions`, `checklist_items/_attendance_rules`).
- Theme preview (`theme_previews/show`): its table is a sample of the theme, not data.
- Upstream views (`audit_logs/show`, `relationship_types/show`, `time_clock_punches/_time_clock_punches`): rule 6. Raise upstream if wanted.

## What it does

Each table gets the one switch from fork-spec "Tables": `choose_columns: "<area>-<page>"` on `shared/_people_table`, or `data: column_chooser_data("<area>-<page>")` on a wrapper around the filter bar and table. Headings that must stay get `data-column-chooser-fixed`; headings holding controls get `data-column-chooser-label`. A record page's small detail table gets it too.

## Tests

Per screen, a controller or system test that the wrapper carries the column-chooser controller (`data-controller` includes `column-chooser table-filter`) and a `column_chooser_key_value`. Run each branch's tests and RuboCop.

## Fork notes

One small task per branch, so they can run in parallel. No migrations, settings or flags (display only). Rebuild integration once after all are merged.
