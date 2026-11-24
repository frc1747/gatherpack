# BL-064: Forms screens to the standard (the rest after BL-060)

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | high |
| Status | done (feature/forms; feature/my-gatherpack-forms phone test follows at the next rebuild) |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/forms`, `feature/my-gatherpack-forms`; after BL-062 and BL-060 |
| Upstream issue / PR | none |

## Summary

BL-060 fixes the form page itself. The screens around it still disagree: a person's response page can show up to eleven buttons, the reminder page's Send is yellow, the Edit page leaves with a yellow "Back", the index has two "Printable list" buttons and a blue New Form. Move BL-060's page onto the screen kit and bring the rest of Forms to the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Form page `forms/show.html.erb` (after BL-060) | BL-060 markup | swap for `_page_header` + `_state_line`, `_filter_bar` (team, status, More choices, Print/CSV), `_people_table`, `_action_row` (Edit, Remind (n), More) |
| Response `form_responses/show.html.erb:103-131` | job buttons by state (Fill in / Continue / Review answers / Update answers / Submit, each `btn-primary`), Discard draft (`btn-outline-dark`), All responses, See totals (`btn-secondary`), Withdraw response (`btn-outline-danger`), plus Continue/Discard update (`:77-79`, small) | `_action_row`: the one job button for the state; More: See totals (shared-totals viewers), Discard draft / Discard update, Withdraw response (destructive, last). "All responses" goes (breadcrumb). The in-progress-update notice keeps its small Continue link only |
| Response edit `form_responses/edit.html.erb:106-117` | Back or Cancel `btn-warning`, Save for later `btn-secondary`, Submit `btn-primary`; Discard this draft/update `btn-sm btn-danger` below | Cancel (`btn-secondary`, always "Cancel"), Save for later (`btn-secondary`), Submit (`btn-primary`, last); Discard moves to the response page's More |
| Submission `form_submissions/show.html.erb` | "Back" `btn-warning`, bare table | no Back (breadcrumb); `table-responsive` |
| Reminder `forms/reminder.html.erb:53-56` | Send `btn-warning`, Update preview `btn-secondary`, Cancel `btn-outline-secondary` | Cancel (`btn-secondary`), Update preview (`btn-secondary`), Send (`btn-primary`, last) |
| Edit `forms/edit.html.erb:39-41` | tabs (kept); "Back" `btn-warning`, Save | Cancel (`btn-secondary`), Save; the badges-off alert (`:20-26`) becomes a `_state_line`-style note under the tabs, not an alert |
| Questions tab `forms/_edit_questions.html.erb` | per-question Save `btn-secondary btn-sm` rows | row buttons `btn-sm btn-outline-secondary`; Remove `btn-sm btn-outline-danger` |
| Question new/edit `form_questions/{new,edit}.html.erb` | Cancel `btn-warning`, Save | Cancel `btn-secondary`, Save |
| Index `forms/index.html.erb:50,85,95` | "Printable list" twice, New Form `btn-primary` | upstream's filter card: New Form (`btn-success`), Search, Clear Search; Printable list once, in More |
| Preview, Audience `forms/preview.html.erb`, `forms/audience.html.erb` | "Back" `btn-warning`; preview table bare | breadcrumb only; `table-responsive` |
| Shared totals `forms/tally.html.erb` (totals-only viewers after BL-060) | bare table | BL-060's totals partial; `table-responsive` |
| Profile tab `person_forms/show.html.erb:32-77` | Sign / Fill in small `btn-primary` per row | row buttons stay `btn-sm btn-primary` (they are the row's one job, like My GatherPack); table in `_people_table`-style wrapper |

Taking answers (BL-060) is the pattern every other feature's state choice copies.

## Works differently

- A response page shows one job button and a More menu; Withdraw and Discard move into More.
- The forms index loses its second Printable list button.

## Tests

- Response page: for each response state, exactly one job button outside More; Withdraw is the last More item and keeps its confirm; a shared-totals viewer sees See totals in More and no answers.
- Reminder: Send submits; Update preview re-renders; Cancel returns to the form page with the team kept.
- Edit tabs: footer shows Cancel then Save on Details, Permissions and Responses tabs.
- Index: one Printable list link (in More); New Form present only for creators.
- Existing forms tests stay green; none weakened.

## Fork notes

- No flag (`feature_forms` already gates the feature). No upstream files touched.
- Connectors: check `feature/my-gatherpack-forms` rows and `feature/forms-auto-reminders` reminder note still render in the new footer.
- Retake gphelp screenshots: form response (member and leader), reminder, form edit tabs, forms list.
