# BL-066: Checklist screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | high |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/checklists`, `feature/checklists-connectors`, `feature/my-gatherpack-checklists`; after BL-062 |
| Upstream issue / PR | none |

## Summary

The checklist page puts its actions in the header (Edit, Take Snapshot, Recompute, Copy) in four styles, sets its state through a bare Draft/Active/Archived select, and its setup page stacks the details form, items, rules and access on one page. Its forms already use the inline "Save anyway" question, which is the standard. Bring the record and setup pages in line. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Checklist `checklists/show.html.erb:4-57` | header actions: Edit (`btn-warning`), Take Snapshot (`btn-secondary`), Recompute (`btn-outline-secondary`), Copy (`btn-info`); status badge only when not active; Restore `btn-sm`; "as of" date form with Show/Today | header card with a state line ("Counting now", "Not counting yet: only the people who run it see it", "Archived"); `_filter_bar` (team, status, as-of date, Print at the right); `_people_table`; `_action_row` in the footer: Edit, Take Snapshot, More (Recompute, Copy, Archive or Restore, then Delete). Snapshots card stays below |
| Setup `checklists/edit.html.erb`, `_setup.html.erb`, `_form.html.erb:20` | details form, then items, rules and access stacked; status select | link tabs: **Details · Items (n) · Who it covers · Access**; replace the status select with **Counting**: *Not yet* (draft: only the people who run it see it, nobody is notified) / *Yes, counting now* (active: people see their progress) and leave Archive to the record page's More; footer Cancel, Save; "Delete checklist" (`btn-outline-danger btn-sm` at the bottom) moves to the record page's More |
| Item new/edit `checklist_items/{new,edit}.html{,+count}.erb` | Save anyway inline question (kept), Cancel `btn-link`, Add rule `btn-primary btn-sm`, Remove `btn-link btn-sm` | Cancel `btn-secondary` before Save; Add rule `btn-sm btn-outline-secondary`; Remove `btn-sm btn-outline-danger` |
| Copy, Confirm `checklists/copy_form.html.erb`, `checklists/confirm.html.erb` | Cancel `btn-link`; confirm button `btn-warning`; copy table bare | one-step action page: Cancel `btn-secondary`, then "Copy" / the effect (`btn-primary`); `table-responsive` |
| Excuses `checklist_excuses/{new,meeting}.html.erb` | Cancel `btn-link`, Remove `btn-link btn-sm` | Cancel `btn-secondary`; Remove `btn-sm btn-outline-danger` |
| Index `checklists/index.html.erb` | Search, New Checklist (`btn-success`) in the body | upstream filter card shape: New Checklist, Search, Clear Search in the footer |
| Snapshot `checklist_lists/show.html.erb` | table, no actions | header card names the date taken; Print at the right of the table |
| Profile tab `person_checklists/show.html.erb`, My GatherPack rows | read-only | none beyond the shared status badge words |

The enum stays (`draft`, `active`, `archived`); only the screen words change.

**Archive and Restore** (lifecycle actions, not part of Counting). Checklists have `restore` (`config/routes/checklists.rb:8`, `checklists_controller.rb:112-115`, `ChecklistPolicy#restore?` at `checklist_policy.rb:84`) but no `archive`; today only the status select archives. Add:

- Route: `post :archive` in the member block beside `restore`.
- Policy: `archive?` = `!record.archived? && record.organizer?(person)`.
- Controller: `archive` sets `archived` and redirects to the checklist ("Checklist archived. It's read-only until restored.").
- More items: **Archive** (confirm "Archive this checklist? It becomes read-only; results and snapshots are kept.") or **Restore** (existing route; confirm "Restore this checklist? It starts counting again."), then **Delete**. An archived checklist's Edit page isn't reachable (`update?` is false), so Counting never needs an Archived option.

## Works differently

- Header buttons move to the footer; Recompute and Copy move into More.
- Counting replaces the status select; Archive (new route) and Restore sit in the record's More; Delete moves from the setup page to the record's More.
- The setup page has tabs.

## Tests

- Footer shows Edit, Take Snapshot and More for a manager; a reader without manage sees none.
- Each Counting choice sets the status; the state line matches.
- `archive`: an organizer archives an active and a draft checklist (status `archived`, results kept); a non-organizer can't; an archived one can't be archived again.
- `restore` (existing): still sets `active`; More shows Restore only when archived and Archive only when not, each with its confirm.
- Setup tabs save their own parts; the Save anyway question still appears above Save when a change affects results.
- Delete from More keeps its confirm and the same `destroy?` rule as today.
- Existing checklist and connector tests stay green; none weakened.

## Fork notes

- No flag (`feature_checklists` gates it). No upstream files touched.
- Retake gphelp screenshots: checklist page, setup tabs, item edit.
