# BL-065: Sign-up sheet screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | high |
| Status | done (feature/signups, not yet released) |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/signups`, `feature/signup-credit`, `feature/checklists-connectors` (the sheet panel); after BL-062 |
| Upstream issue / PR | none |

## Summary

Sign-ups uses "Set up" where everything else says Edit, sets a sheet's state with a bare Draft/Open/Closed/Archived select, labels the sheet's delete button "Delete" or "Archive" depending on permissions with an "Are you sure?" dialog, and stacks six setup sections on one long page. Members' own "Cancel" (to drop a sign-up) is red and shares a word with leaving a form. Bring the sheet, roster and setup pages to the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Sheet `signup_sheets/show.html.erb:4-28` | status badge (`status.humanize`); footer Set up (`btn-warning`), Roster (`btn-info`), Delete-or-Archive (`btn-danger`, "Are you sure?"); member rows Change (`btn-sm btn-primary`), Cancel (`btn-sm btn-danger`) | `_page_header` with a state line ("Taking sign-ups until Dec 5", "Not taking sign-ups yet", "Closed"); `_action_row`: Edit, Roster (`btn-secondary`), More (Archive, or Restore when archived, then Delete only when `destroy?` allows it, worded "Delete this sheet?"). Member row buttons: Change (`btn-sm btn-outline-secondary`), **Cancel sign-up** (`btn-sm btn-outline-danger`, confirm "Cancel your sign-up for Sat Dec 6?") |
| Roster `signup_sheets/roster.html.erb` | Add a sign-up (`btn-success`), Message (`btn-primary`), Print (`btn-secondary`), Set up (`btn-warning`), Filter, Clear, Mark all brought | `_filter_bar` (Filter/Clear, Print at the right); `_action_row`: Add a sign-up (`btn-success`), Message, More (Mark all brought). "Set up" goes (breadcrumb back to the sheet, Edit there) |
| Setup `signup_sheets/edit.html.erb:19-26`, `_form.html.erb:22` | the details form, then "Set up the sheet" with positions, dates, slots, organizers, audience stacked; Roster `btn-info btn-sm` in the header; status select with hint "Members can sign up while it's open." | link tabs like `forms/edit`: **Details · Positions · Dates · Organizers · Who can sign up** (slots stay inside Dates). On Details, replace the status select with **Taking sign-ups**: *Not yet* (only organizers see it) / *Yes, open now* (members who can sign up see it) / *No, closed* (people can see their sign-ups, not change them); archiving is not in this choice. An archived sheet's Edit page shows the state line "Archived" and no choice until it's restored. Footer Cancel, Save |
| New `signup_sheets/new.html.erb` | Cancel `btn-warning`, Save | Cancel `btn-secondary`, Save; Taking sign-ups defaults to *Not yet* |
| Positions, dates, slots, messages, roster sign-ups (`signup_positions/*`, `signup_sheet_events/*`, `signup_slots/index`, `signup_messages/new`, `roster_signups/*`) | "Back to the sheet"/"Back to the roster" `btn-warning`; Cancel `btn-warning`; `signup_sheet_events/new` Filter/Clear/Add these dates | Cancel `btn-secondary`, Save last; no Back buttons (breadcrumb); Remove `btn-sm btn-outline-danger` |
| Index `signup_sheets/index.html.erb` | New Sign-up Sheet `btn-success`, bare table | upstream filter card shape; `table-responsive`; status column in the same words as the state line |
| Member sign-up `signups/{new,edit}.html.erb` | Back `btn-secondary`, Save | Cancel `btn-secondary`, Save |
| Event panel `signup_sheets/_event_panel.html.erb` | Sign up `btn-sm btn-primary` | see BL-067 |

Status words: the enum stays (`draft`, `open`, `closed`, `archived`; MCP and the reminder job use it); only the screen words change.

**Archive and Restore** (lifecycle actions, not part of Taking sign-ups). Today the only way to archive is `DELETE`, which archives only when `destroy?` is false (`signup_sheets_controller.rb:93-101`), and nothing restores (`config/routes.rb:153-161` has no member routes but `roster`). Add:

- Routes: `member { get :roster; post :archive; post :restore }`.
- Policy (`signup_sheet_policy.rb`): `archive?` = `organizer? && !record.archived?`; `restore?` = `organizer? && record.archived?`.
- Controller: `archive` sets `archived` and redirects to the sheet ("Sheet archived."); `restore` sets `closed` (back, but not taking sign-ups until someone chooses to) and redirects to the sheet ("Sheet restored. It isn't taking sign-ups.").
- More items: **Archive** (`button_to` POST, confirm "Archive this sheet? It's hidden from lists; sign-ups are kept.") and **Restore** (confirm "Restore this sheet? It comes back closed."). **Delete** appears only when `destroy?` is true and uses `DELETE`. The screen never sends `DELETE` to archive; `destroy` keeps its archive fallback only for other callers.

## Works differently

- "Set up" is called Edit; the setup page has tabs.
- Taking sign-ups replaces the status select. Archive and a new Restore are in the sheet page's More menu, on their own routes; Delete shows only for sheets with no sign-ups.
- Members' "Cancel" becomes "Cancel sign-up" with a confirm that names the date.

## Tests

- Each Taking sign-ups choice sets the status; an archived sheet shows "Archived" in the state line and its Edit page offers no choice.
- `archive`: an organizer archives a sheet that has sign-ups and one that has none; both are kept (count unchanged), status `archived`. A non-organizer gets the usual not-authorized response. An already archived sheet can't be archived again.
- `restore`: an organizer restores an archived sheet to `closed`; a non-organizer can't; a sheet that isn't archived can't be restored.
- More shows Archive (not archived) or Restore (archived), each with its confirm text; Delete shows only when `destroy?` is true, and no Archive control sends `DELETE`.
- Sheet page footer: Edit, Roster, More for an organizer; a member sees none of them.
- Setup tabs: each tab saves its own part; the Positions and Dates tabs keep their existing add/remove flows.
- Member Cancel sign-up asks with the date and cancels; the cutoff rule is unchanged.
- Existing signups, signup-credit and checklists-connectors tests stay green; none weakened.

## Fork notes

- No flag (`feature_signups` gates the feature). No upstream files touched.
- MCP descriptions (`feature/mcp-signups`) still say "status"; leave the field, check they don't name the old button words.
- Retake gphelp screenshots: sheet (member and organizer), roster, every setup tab.

- Archived sheets are hidden from the list. People who run sheets get a "Which sheets" choice in the list's filter card that lists the archived sheets they run; Restore is on the sheet's page.
