# BL-020: Commitments on the person's profile (features can't add profile tabs)

| | |
|---|---|
| Kind | upstream feature |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-12 |
| Upstream base checked | `86ab397` |
| Planned branch | `feature/profile-tabs` (from `upstream/main`), then a one-line registration in `feature/commitments` |
| Upstream issue / PR | none yet |

## Summary

`feature/commitments` already has a page for one person's commitments, `GET /people/:person_id/commitments` (`person_commitments#show`, with its own policy: the person sees all of theirs, anyone else only the ones they run or whose group they're related to). Nothing links to it from the profile. The signups spec (§4, "Person who owes") calls for a **My commitments** section on the person's profile, and parents need it most: it's where they'd look for what their family still owes.

It isn't linked because the profile's tab bar is hard-coded in an upstream view. Adding a "Commitments" tab means editing that file in `feature/commitments`, which is the "edit, don't add" case the fork strategy tells us to avoid: every later upstream change to the tab bar would conflict, and the edit would follow the branch into any upstream PR. So this is a seam first: let features register profile tabs the way they already register nav items, then commitments (and later sign-ups, "My sign-ups") add a tab from their initializer without touching the view.

## Where things are (upstream `86ab397`)

- `app/views/people/_show_shared.html.erb:3-29`: the profile tab bar (Overview, Teams, Relationships, Recent Activity, then Calendar and Statistics behind `GatherPack::Features.enabled?` checks at lines 17 and 22). The list ends at line 28 with no slot for features.
- `config/initializers/features.rb:16-22` and `:50`: features already register sidebar links with `GatherPack::Feature::NavItem` (label, path, icon). There is no equivalent for profile tabs.
- `feature/commitments`: `config/routes.rb` (`get "people/:person_id/commitments", to: "person_commitments#show", as: :person_commitments`), `app/controllers/person_commitments_controller.rb`, `PersonCommitmentsPolicy`.
- `feature/extension-registries` (BL-018) is the same kind of seam for settings and hook events; this would sit beside it.

## Proposed fix

1. Seam branch `feature/profile-tabs` from `upstream/main`: a `profile_tabs` list on `GatherPack::Feature` (label, path proc taking the person, optional `visible:` proc taking the user and person). `_show_shared.html.erb` renders the registered tabs of enabled features after its built-in ones, with the same active-tab test. One small upstream view edit, generic and useful to plugins; record it in `FORK.md`.
2. `feature/commitments` registers "Commitments" → `person_commitments_path(person)`, visible when `PersonCommitmentsPolicy#show?` allows it and the person has at least one visible commitment (so the tab doesn't appear on profiles where it would be empty). The page itself needs the profile's tab bar (`render "people/show_shared"`) so it reads as part of the profile.
3. Declare the dependency: commitments (or a small `feature/commitments-profile-tab` branch, if commitments should stay independent of the seam) comes after `feature/profile-tabs` in the manifest.

## Tests

- A registered tab shows on the profile when its feature is enabled and `visible:` is true, and is marked active on its own page.
- Hidden when the feature is off or `visible:` is false.
- Commitments tab: shown to the person and to a parent related through a grouping relationship; not shown to an unrelated member, or on a profile with no visible commitments.

## Fork strategy notes

The seam is upstream-intended; confirm with Corey before any issue or PR. Until it lands, the page is reachable only from the Commitments index.
