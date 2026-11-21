# BL-067: Event page panels to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/forms`, `feature/signups`, `feature/event-type-checkin-fields`; after BL-062 and BL-060 |
| Upstream issue / PR | none |

## Summary

The event page is upstream's (`events/show.html.erb`); the fork adds panels below it for the event's forms and sign-up sheets. Each panel draws its own header and buttons: the forms panel has up to five small buttons per form in three styles, the sign-ups panel one. Give every panel the same shape (a card with a heading, one row per thing, one small row button that opens it, one "New …" link at the bottom for leaders). The page's own footer (Print, Arrange, Edit, Delete) is upstream's and is listed in the spec as an upstream edit for Corey to approve; this item doesn't change it. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Forms panel `forms/_event_panel.html.erb:33-34` | per form: Results, Tally (`btn-sm btn-outline-primary`); New form for this event (`btn-sm btn-secondary` and `btn-sm btn-outline-secondary`), Printable list for this event (`btn-sm btn-secondary`) | per form: state words ("Taking answers until …") and one **Responses** row button (`btn-sm btn-outline-secondary`, BL-060); footer link "New form for this event" (`btn-sm btn-outline-secondary`); Printable list goes (the form page prints) |
| Sign-ups panel `signup_sheets/_event_panel.html.erb` | Sign up `btn-sm btn-primary` | per sheet: state words and **Sign up** (`btn-sm btn-primary`, the member's job) or **Open** (`btn-sm btn-outline-secondary`) for organizers; footer "New sign-up sheet for this event" for organizers |
| Event types `event_types/*` (upstream) and check-in field screens added by `feature/event-type-checkin-fields` (`checkin_fields/show` edit) | upstream layout | fork additions use the same row buttons (`btn-sm btn-outline-secondary`, Remove `btn-sm btn-outline-danger`); no upstream view change |

Panel shape (both panels): `card` with `card-header` "Forms" / "Sign-up sheets", `list-group-flush` rows (title link, state words, one row button), `card-footer` with the leader-only New link. Empty: "No forms for this event." in muted text, shown only to leaders.

## Works differently

- The forms panel drops Results, Tally and Printable list for one Responses button (with BL-060).

## Tests

- Event page with a form and a sheet: each panel renders one row per item with one row button; a member sees Sign up and no New links.
- A leader sees the New links; the empty line shows only to leaders.
- Existing events, forms and signups tests stay green; none weakened.

## Fork notes

- No flag. No new upstream files touched (the panels' `render` lines in `events/show.html.erb` are already in FORK.md).
- Upstream edit for Corey (in the spec, not this item): `events/show` footer Edit, Print, More (Arrange, Delete).
- Retake gphelp screenshots: event page with panels (leader and member).
