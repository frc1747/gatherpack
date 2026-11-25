# BL-073: Setup-only fork screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | low |
| Status | done (all eight branches; not yet released) |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/person-fields`, `feature/managed-lists`, `feature/housekeeping`, `feature/widgets`, `feature/mcp`, `feature/person-merge`, `feature/phone-notifications`, `feature/theme-palette`; after BL-062 |
| Upstream issue / PR | none |

## Summary

The admin-only fork screens mostly copy upstream already. The gaps are small and repeated: yellow Cancel, Archive/Restore and Hide/Show archived as full buttons, `btn-info` and `btn-dark` used for ordinary links, a few bare tables. One pass per branch, each a short commit. Standard: `fork-spec` "Screen design" ("Defined things" for the vocabulary lists); reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Person fields `person_fields/index.html.erb` | New Field (`btn-success`), Preview as… (`btn-primary`), Apply recommended (`btn-info`), Sections (`btn-secondary`), Hide/Show archived (`btn-dark`); rows Archive/Restore | footer: New Field, More (Preview as…, Apply recommended, Sections); Archived as a filter pill; rows Edit / Archive as `btn-sm btn-outline-secondary` |
| Field groups, field new/edit/show (`person_field_groups/*`, `person_fields/{new,edit,show,preview}`) | Cancel `btn-warning`; show has Back `btn-secondary`; groups table bare | Cancel `btn-secondary`; no Back (breadcrumb); `table-responsive` |
| Managed lists `managed_lists/index.html.erb` | 15 buttons: arrows, Edit `btn-outline-warning`, Retire/Restore, Merge per row | rows per "Defined things": small Edit, arrows, Retire (`btn-sm btn-outline-secondary`), Merge in a per-row More; Restore on the archived filter |
| Managed list new/edit/merge | Cancel `btn-warning`; Merge `btn-danger` | Cancel `btn-secondary`; Merge stays `btn-danger` (destructive) |
| Housekeeping `housekeeping/{index,preview}`, `housekeeping_purges/show` | Back `btn-link`, Cancel `btn-link`; bare tables | Cancel `btn-secondary`; no Back; `table-responsive` |
| Widgets `widgets/*` | Cancel `btn-warning`; bare index table | Cancel `btn-secondary`; `table-responsive` |
| Person merge `person_merges/new.html.erb` | Cancel `btn-warning`, preview submit, Merge `btn-danger`; bare table | one-step action page: Cancel `btn-secondary`, Preview (`btn-secondary`), Merge (`btn-danger`, last); `table-responsive` |
| Push keys, email notices, MCP calls (`push_keys/edit`, `email_notices/show`, `mcp/calls/index`) | Cancel `btn-warning`; Replace keys `btn-danger` | Cancel `btn-secondary` |
| Theme palette preview `theme_previews/show.html.erb` | bare table | `table-responsive` |

## Works differently

Nothing a member sees. Admins: person-field extras move into More.

## Tests

- Person fields index: footer New Field and More; Archived pill filters; Archive/Restore rows still work.
- Managed lists: rows reorder, retire, restore and merge as before.
- Each touched form saves and cancels.
- Existing tests on each branch stay green; none weakened.

## Fork notes

- No flags. No upstream files touched.
- Several branches: do them as separate task branches off each feature; none depends on another.
- Retake gphelp screenshots only where the admin help shows them (Person fields, Managed lists).
