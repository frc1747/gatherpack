# BL-065: Sign-up sheet screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | high |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/signups`, `feature/signup-credit`, `feature/checklists-connectors` (the sheet panel); after BL-062 |
| Upstream issue / PR | none |

## Summary

Sign-ups uses "Set up" where everything else says Edit, sets a sheet's state with a bare Draft/Open/Closed/Archived select, labels the sheet's delete button "Delete" or "Archive" depending on permissions with an "Are you sure?" dialog, and stacks six setup sections on one long page. Members' own "Cancel" (to drop a sign-up) is red and shares a word with leaving a form. Bring the sheet, roster and setup pages to the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Sheet `signup_sheets/show.html.erb:4-28` | status badge (`status.humanize`); footer Set up (`btn-warning`), Roster (`btn-info`), Delete-or-Archive (`btn-danger`, "Are you sure?"); member rows Change (`btn-sm btn-primary`), Cancel (`btn-sm btn-danger`) | `_page_header` with a state line ("Taking sign-ups until Dec 5", "Not taking sign-ups yet", "Closed"); `_action_row`: Edit, Roster (`btn-secondary`), More (Archive; Delete when allowed, worded "Delete this sheet and its 14 sign-ups?"). Member row buttons: Change (`btn-sm btn-outline-secondary`), **Cancel sign-up** (`btn-sm btn-outline-danger`, confirm "Cancel your sign-up for Sat Dec 6?") |
| Roster `signup_sheets/roster.html.erb` | Add a sign-up (`btn-success`), Message (`btn-primary`), Print (`btn-secondary`), Set up (`btn-warning`), Filter, Clear, Mark all brought | `_filter_bar` (Filter/Clear, Print at the right); `_action_row`: Add a sign-up (`btn-success`), Message, More (Mark all brought). "Set up" goes (breadcrumb back to the sheet, Edit there) |
| Setup `signup_sheets/edit.html.erb:19-26`, `_form.html.erb:22` | the details form, then "Set up the sheet" with positions, dates, slots, organizers, audience stacked; Roster `btn-info btn-sm` in the header; status select with hint "Members can sign up while it's open." | link tabs like `forms/edit`: **Details · Positions · Dates · Organizers · Who can sign up** (slots stay inside Dates). On Details, replace the status select with **Taking sign-ups**: *Not yet* (only organizers see it) / *Yes, open now* (members who can sign up see it) / *No, closed* (people can see their sign-ups, not change them); Archive stays in More on the sheet page, not in this choice. Footer Cancel, Save |
| New `signup_sheets/new.html.erb` | Cancel `btn-warning`, Save | Cancel `btn-secondary`, Save; Taking sign-ups defaults to *Not yet* |
| Positions, dates, slots, messages, roster sign-ups (`signup_positions/*`, `signup_sheet_events/*`, `signup_slots/index`, `signup_messages/new`, `roster_signups/*`) | "Back to the sheet"/"Back to the roster" `btn-warning`; Cancel `btn-warning`; `signup_sheet_events/new` Filter/Clear/Add these dates | Cancel `btn-secondary`, Save last; no Back buttons (breadcrumb); Remove `btn-sm btn-outline-danger` |
| Index `signup_sheets/index.html.erb` | New Sign-up Sheet `btn-success`, bare table | upstream filter card shape; `table-responsive`; status column in the same words as the state line |
| Member sign-up `signups/{new,edit}.html.erb` | Back `btn-secondary`, Save | Cancel `btn-secondary`, Save |
| Event panel `signup_sheets/_event_panel.html.erb` | Sign up `btn-sm btn-primary` | see BL-067 |

Status words: the enum stays (`draft`, `open`, `closed`, `archived`; MCP and the reminder job use it); only the screen words change.

## Works differently

- "Set up" is called Edit; the setup page has tabs.
- Taking sign-ups replaces the status select. Archive moves to the sheet page's More menu.
- Members' "Cancel" becomes "Cancel sign-up" with a confirm that names the date.

## Tests

- Each Taking sign-ups choice sets the status; Archived sheets show "Archived" in the state line and the choice isn't offered (Restore lives in More).
- Sheet page footer: Edit, Roster, More for an organizer; a member sees none of them.
- Setup tabs: each tab saves its own part; the Positions and Dates tabs keep their existing add/remove flows.
- Member Cancel sign-up asks with the date and cancels; the cutoff rule is unchanged.
- Existing signups, signup-credit and checklists-connectors tests stay green; none weakened.

## Fork notes

- No flag (`feature_signups` gates the feature). No upstream files touched.
- MCP descriptions (`feature/mcp-signups`) still say "status"; leave the field, check they don't name the old button words.
- Retake gphelp screenshots: sheet (member and organizer), roster, every setup tab.
