# BL-070: Commitment screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/commitments`, `feature/signup-credit`, `feature/checklists-connectors`; after BL-062 |
| Upstream issue / PR | none |

## Summary

A commitment's page says "Set up" instead of Edit, shows Set up, Add an adjustment, Print and Delete in one row, and has its own filter and Send buttons. The setup page stacks sources and organizers under the form. Bring them to the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Commitment `commitments/show.html.erb:23-27` | Set up (`btn-warning`), Add an adjustment, Print (`btn-secondary`), Delete (`btn-danger`); Filter, Clear, Send | header summary (who owes, due); `_filter_bar` (team, status, Print at the right); `_people_table`; `_action_row`: Edit, Add an adjustment, More (Send reminder, Delete last) |
| Setup `commitments/edit.html.erb` | form, then sources and organizers stacked; Cancel `btn-warning`; Add … / Add organizer `btn-secondary` | link tabs **Details · What counts · Organizers**; Cancel `btn-secondary`, Save; Add buttons `btn-sm btn-outline-secondary` |
| New, adjustments, sources (`commitments/new`, `commitment_adjustments/new*`, `commitment_sources/{new,edit}*`) | Cancel `btn-warning` | Cancel `btn-secondary`, Save |
| Index `commitments/index.html.erb` | New Commitment only; bare table | upstream filter card shape; `table-responsive` |

## Works differently

- "Set up" is called Edit, and the setup page has tabs.

## Tests

- Footer shows Edit, Add an adjustment, More for an organizer; Delete last in More with its confirm.
- Setup tabs save their parts; signup-credit and checklist sources still appear under What counts.
- Existing commitments, signup-credit and checklists-connectors tests stay green; none weakened.

## Fork notes

- No flag (`feature_commitments` gates it). No upstream files touched.
- Retake gphelp screenshots: commitment page, setup tabs.
