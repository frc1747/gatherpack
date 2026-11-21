# BL-068: People and Teams profile screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/profile-tabs`, `feature/forms`, `feature/checklists`, `feature/commitments-profile-tab`, `feature/intake`, `feature/housekeeping`; after BL-062 |
| Upstream issue / PR | none |

## Summary

Profiles already use the standard's tabs (`people/_show_shared`, `teams/_show_shared`, link tabs per part). The fork's tabs (Forms, Checklists, Commitments) each draw their own table and row buttons, and the team applications page the fork extended has twelve small buttons in five styles. Give the fork's tabs one table shape and the applications page an action row. `people/show`'s own footer is upstream's and is listed in the spec as an upstream edit for Corey to approve. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Forms tab `person_forms/show.html.erb` | two tables (own, wards'), row buttons Sign / Fill in `btn-sm btn-primary` | `_people_table`-style table per section, status badge words shared with the form page; row buttons unchanged (the row's job) |
| Checklists tab `person_checklists/show.html.erb` | table, no actions | `table-responsive`, status badge words from the checklist |
| Commitments tab `person_commitments/show.html.erb` | table, no actions | `table-responsive`; empty line "No commitments." |
| Team applications `teams/applications.html.erb` (upstream view; intake renders `intake/membership_applications/_bulk` and `_details`, `intake/matches/_flag`) | upstream rows: View (`btn-sm btn-outline-primary`), Approve (`btn-sm btn-success`), Deny (`btn-sm btn-danger`); intake partials add Link (`btn-sm btn-outline-primary`), Keep separate (`btn-sm btn-outline-secondary`), bulk Approve/Deny (`btn-sm btn-outline-danger` Deny) | intake partials only: Deny `btn-sm btn-danger` to match upstream's row; Link and Keep separate in a small per-row More. Upstream's View/Approve/Deny unchanged |
| Membership applications `membership_applications/index` (housekeeping additions) | "Delete as spam" `btn-sm btn-outline-danger` beside Approve/Withdraw | fork's Delete as spam moves into the per-row More, last |
| Team move `team_moves/{new,preview}.html.erb` | Cancel `btn-link`; table bare | one-step action page: Cancel `btn-secondary`, Move (`btn-primary`); `table-responsive` |

## Works differently

- On team applications, Link and Keep separate move into a small More per row.

## Tests

- Each fork profile tab renders inside `_show_shared`'s tabs with its table and empty line.
- Team applications: a flagged match row shows upstream's buttons and a More holding Link and Keep separate; both still work.
- Existing people, teams, intake and housekeeping tests stay green; none weakened.

## Fork notes

- No flag. Upstream files touched: none new: `teams/applications.html.erb` and `membership_applications/index.html.erb` are already in FORK.md for intake and housekeeping, and the changes stay in the fork's partials.
- Upstream edit for Corey (in the spec): `people/show` footer Edit first (rename "Edit Profile"), rest in More.
- Retake gphelp screenshots: person Forms/Checklists/Commitments tabs, team applications.
