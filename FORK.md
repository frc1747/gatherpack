# HBR Fork Status

Status register for the HBR fork of GatherPack. The rules live in
[`fork/STRATEGY.md`](fork/STRATEGY.md); the merge order lives in
[`fork/features.txt`](fork/features.txt).

- Upstream: https://github.com/GatherPack/gatherpack
- Fork: https://github.com/seliger/gatherpack
- Upstream base at setup: `32e8023` (2026-10-02)

## Features

| Branch | Status | Upstream link | Depends on | Upstream files touched | Migrations | Flag | Notes |
|---|---|---|---|---|---|---|---|
| `feature/audit-log-nil-changes` | wip | — | — | `app/controllers/audit_logs_controller.rb`, `app/views/audit_logs/show.html.erb` | — | — | Audit log show page no longer crashes when `object_changes` is nil. No test coverage yet. From `5ececba` (`fix/audit-log-nil-object-changes`). |
| `feature/membership-create-policy` | wip | — | — | `app/policies/membership_policy.rb`, `test/policies/membership_policy_test.rb` | — | — | `MembershipPolicy#create?`: managers add anyone; others may only join an open team themselves, never as manager. From `4f16842` (`search-and-add-screens`). |
| `feature/unique-assignments` | wip | — | — | `app/models/badge_assignment.rb`, `app/models/membership.rb`, `db/schema.rb` | `20260927120000_add_unique_index_to_badge_assignments.rb`, `20260927130000_add_unique_index_to_memberships.rb`, `20260927140000_add_unique_index_to_checkins.rb` | — | Unique indexes plus model validations. Migrations are reversible and reproduce `db/schema.rb` exactly from an empty database. No test coverage of its own; exercised by `feature/search-and-add`. From `ce0f8cf` (`search-and-add-screens`). |
| `feature/membership-filters-fix` | wip | — | — | `app/controllers/memberships_controller.rb`, `test/controllers/memberships_controller_test.rb` | — | — | Fixes the Parent Managers and Child Team Members filters on team memberships. From `468d74f` (`search-and-add-screens`). |
| `feature/search-and-add` | wip | — | `feature/membership-filters-fix`, `feature/membership-create-policy`, `feature/unique-assignments` | `app/assets/stylesheets/_cards.scss`, `app/controllers/badge_assignments_controller.rb`, `app/controllers/checkins_controller.rb`, `app/controllers/memberships_controller.rb`, `app/helpers/memberships_helper.rb`, `app/views/badge_assignments/index.html.erb`, `app/views/checkins/_checkins.html.erb`, `app/views/memberships/by_person.html.erb`, `app/views/memberships/by_team.html.erb`, `config/routes.rb`, plus 6 test files | — | — | Search-and-add screens for badges, memberships, and checkins. Textually depends on membership-filters-fix (both edit `memberships_controller.rb`); its tests also need membership-create-policy (1 test) and unique-assignments (2 tests). From `1a18f52` (`search-and-add-screens`). |
| `feature/person-fields` | wip | Issue [#489](https://github.com/GatherPack/gatherpack/issues/489) | — | — | — | — | Design spec only (`docs/person-fields-spec.md`), no code. Not in the manifest. |

## Provenance

The fork was reorganized on 2026-10-02. Every commit on the feature branches
above is a patch-identical cherry-pick of the original commit named in its
Notes. The original branches (`fix/audit-log-nil-object-changes` at `dd50a02`,
`search-and-add-screens` at `88546bd`, and `main` at `00bec2c`) are preserved
in `archive/gatherpack-pre-hbr-2026-10-02.bundle` in the workspace parent
folder, with a ref listing alongside it.

Previously upstreamed work, no longer carried: Resend gateway (PR #485), stale
fixtures (#484), Mission Control auth (#482), blank color crash (#507), manager
person-param scoping (#513).

## Running `bin/fork-rebuild` before branches are pushed

The script reads `origin/` refs by default. To build from local branches, run
`REF_PREFIX= bin/fork-rebuild`. It checks out `hbr/integration` in the current
worktree, so run it from a dedicated integration worktree rather than
`platform/`.
