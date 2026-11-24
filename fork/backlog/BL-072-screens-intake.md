# BL-072: Intake (registration) screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | low |
| Status | done (feature/intake, feature/intake-checklist; not yet released) |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/intake`, `feature/intake-checklist`; after BL-062 |
| Upstream issue / PR | none |

## Summary

The leader side of Intake has no breadcrumbs on any of its five pages, closes a registration with a yellow "Close now" button, uses `btn-primary` for Edit and `btn-success` for Save, and its tables don't scroll on phones. The public pages (join, verify, guardian confirm) already follow the "public page" kind and stay as they are. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Registration `intake/registrations/show.html.erb` | no breadcrumb; Edit (`btn-primary`), Copy, Waiting to finish (`btn-outline-primary`), Close now (`btn-warning`), Delete (`btn-danger`); bare table | breadcrumb; header state line ("Taking registrations until Sep 1", "Closed Sep 1"); `_action_row`: Edit, Waiting to finish, More (Copy, Delete last); `table-responsive` |
| Registration edit/new `intake/registrations/{edit,new}.html.erb` | no breadcrumb; Save `btn-primary`/`btn-success`, Cancel `btn-outline-secondary`; open/close times only | breadcrumb; **Taking registrations** choice: *Not yet* / *Yes, open now* / *No, closed*, with the opening and closing times under it. There is no state column (open = between `opens_at` and `closes_at`, `app/models/intake/registration.rb:3-4,73-81`), so the choice only sets times: *Yes, open now* sets `opens_at` to now when it's in the future and clears a past `closes_at`; *No, closed* sets `closes_at` to now (today's Close now, `show.html.erb:11`); *Not yet* needs a future `opens_at`. Cancel `btn-secondary`, Save |
| List `intake/registrations/index.html.erb` | no breadcrumb; Hide/Show archived buttons; New Registration; bare table | breadcrumb; upstream filter card with an Archived pill in `_filter_bar`; `table-responsive` |
| Waiting `intake/registrations/waiting.html.erb` | no breadcrumb; Back (`btn-outline-secondary`), per-row Link, Keep separate and others in outline styles | breadcrumb, no Back; per row one job button and a small More |
| Spam people `intake/spam_people/show.html.erb` | Delete then Cancel | Cancel (`btn-secondary`), Delete (`btn-danger`, last) |
| Public pages `intake/join/*`, `intake/verifications/*`, `intake/guardian_confirmations/*`, `intake/email_changes/*`, `intake/me/show` | one card, one primary button | none (already the public-page kind); `intake/me` Save/Add `btn-outline-primary` become `btn-primary` for the step's one action |

## Works differently

- "Close now" goes; closing is the Taking registrations choice on the Edit page.

## Tests

- All five leader pages render a breadcrumb.
- Choosing *No, closed* and saving closes the registration (same effect as Close now today, including the closed page for joiners).
- Registration page footer: Edit, Waiting to finish, More; Delete last with its confirm.
- Existing intake tests stay green; none weakened.

## Fork notes

- No flag (`feature_intake` gates it). No upstream files touched.
- Retake gphelp screenshots: registration page, edit, waiting list.
