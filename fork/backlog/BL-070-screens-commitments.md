# BL-070: Commitment screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | done (feature/commitments, checklists-connectors, signup-credit; not yet released) |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/commitments`, `feature/signup-credit`, `feature/checklists-connectors`; after BL-062 |
| Upstream issue / PR | none |

## Summary

A commitment's page says "Set up" instead of Edit, shows Set up, Add an adjustment, Print and Delete in one row, and has its own Filter and Clear buttons (`_progress_table.html.erb:14-15`) and an always-open compose card with Send at the bottom of the page (`_message_form.html.erb`, rendered at `show.html.erb:36`). The setup page stacks sources and organizers under the form. Bring them to the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Commitment `commitments/show.html.erb:23-36`, `_progress_table.html.erb:14-15`, `_message_form.html.erb:1-17` | Set up (`btn-warning`), Add an adjustment, Print (`btn-secondary`), Delete (`btn-danger`); Filter, Clear in the table; compose card (Subject, Message, Send `btn-primary`) always open below | header summary (who owes, due); `_filter_bar` (team, status, Print at the right); `_people_table`; `_action_row`: Edit, **Remind (n)** (`btn-primary`, the page's job, as in Forms; n = people who haven't met it; hidden when n is 0), More (Add an adjustment, Delete last). Remind opens the existing compose card in place (Bootstrap collapse on `#message`, collapsed by default, open again after a validation error); no new page or route. The card's Send, its confirm and `POST message` are unchanged |
| Setup `commitments/edit.html.erb` | form, then sources and organizers stacked; Cancel `btn-warning`; Add … / Add organizer `btn-secondary` | link tabs **Details · What counts · Organizers**; Cancel `btn-secondary`, Save; Add buttons `btn-sm btn-outline-secondary` |
| New, adjustments, sources (`commitments/new`, `commitment_adjustments/new*`, `commitment_sources/{new,edit}*`) | Cancel `btn-warning` | Cancel `btn-secondary`, Save |
| Index `commitments/index.html.erb` | New Commitment only; bare table | upstream filter card shape; `table-responsive` |

## Works differently

- "Set up" is called Edit, and the setup page has tabs.
- The message card is folded away until Remind is pressed; Add an adjustment moves into More.

## Tests

- Footer shows Edit, Remind (n) and More for an organizer; More holds Add an adjustment and Delete (last, with its confirm); Remind is hidden when everyone has met it.
- Remind opens the compose card (system test); sending still emails each open person once; a blank subject reopens the card with the error.
- Setup tabs save their parts; signup-credit and checklist sources still appear under What counts.
- Existing commitments, signup-credit and checklists-connectors tests stay green; none weakened.

## Fork notes

- No flag (`feature_commitments` gates it). No upstream files touched.
- Retake gphelp screenshots: commitment page, setup tabs.
