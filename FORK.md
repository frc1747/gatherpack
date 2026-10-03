# HBR Fork Status

Status register for the HBR fork of GatherPack. The rules live in
[`fork/STRATEGY.md`](fork/STRATEGY.md); the merge order lives in
[`fork/features.txt`](fork/features.txt).

- Upstream: https://github.com/GatherPack/gatherpack
- Fork: https://github.com/frc1747/gatherpack
- Upstream base at setup: `32e8023` (2026-10-02)

## Features

| Branch | Status | Upstream link | Depends on | Upstream files touched | Migrations | Flag | Notes |
|---|---|---|---|---|---|---|---|
| `feature/audit-log-nil-changes` | proposed | PR [#515](https://github.com/GatherPack/gatherpack/pull/515) | — | `app/controllers/audit_logs_controller.rb`, `app/views/audit_logs/show.html.erb` | — | — | Audit log show page no longer crashes when `object_changes` is nil. No test coverage yet. From `5ececba` (`fix/audit-log-nil-object-changes`). |
| `feature/membership-create-policy` | wip | — | `feature/membership-filters-fix` | `app/policies/membership_policy.rb`, `test/policies/membership_policy_test.rb` | — | — | `MembershipPolicy#create?`: managers add anyone; others may only join an open team themselves, never as manager. From `4f16842` (`search-and-add-screens`). |
| `feature/unique-assignments` | wip | — | `feature/membership-create-policy` | `app/models/badge_assignment.rb`, `app/models/membership.rb`, `db/schema.rb` | `20260927120000_add_unique_index_to_badge_assignments.rb`, `20260927130000_add_unique_index_to_memberships.rb`, `20260927140000_add_unique_index_to_checkins.rb` | — | Unique indexes plus model validations. Migrations are reversible and reproduce `db/schema.rb` exactly from an empty database. No test coverage of its own; exercised by `feature/search-and-add`. From `ce0f8cf` (`search-and-add-screens`). |
| `feature/membership-filters-fix` | proposed | PR [#516](https://github.com/GatherPack/gatherpack/pull/516) | — | `app/controllers/memberships_controller.rb`, `app/views/memberships/by_team.html.erb`, `test/controllers/memberships_controller_test.rb` | — | — | Fixes the Name search, Parent Managers, and Child Team Members filters on team memberships. Filters from `468d74f` (`search-and-add-screens`); name search added 2026-10-02 (upstream bug from `203bfeb`, shipped first in `v0.0.0-hbr.2`). |
| `feature/search-and-add` | wip | — | `feature/membership-filters-fix` | `app/assets/stylesheets/_cards.scss`, `app/controllers/badge_assignments_controller.rb`, `app/controllers/checkins_controller.rb`, `app/controllers/memberships_controller.rb`, `app/helpers/memberships_helper.rb`, `app/views/badge_assignments/index.html.erb`, `app/views/checkins/_checkins.html.erb`, `app/views/memberships/by_person.html.erb`, `app/views/memberships/by_team.html.erb`, `config/routes.rb`, plus 6 test files | — | — | Search-and-add screens for badges, memberships, and checkins. Needs all three branches below it, so they are stacked as a chain (filters-fix → create-policy → unique-assignments → search-and-add): it shares `memberships_controller.rb` with filters-fix, and its tests need create-policy (1 test) and unique-assignments (2 tests). The chain's lower links have no real dependency on each other; they are stacked only so search-and-add has a single base. filters-fix sits at the bottom (restacked 2026-10-02) so it can go upstream on its own. From `1a18f52` (`search-and-add-screens`). |
| `feature/brakeman-8.1` | carried | — | — | `Gemfile.lock` | — | — | Temporary. Bumps brakeman 8.0.6 → 8.1.0 because `bin/brakeman` uses `--ensure-latest`, which fails upstream's `scan_ruby` (and so blocks image publishing) whenever a newer brakeman exists. Retire as soon as upstream's lockfile has brakeman ≥ 8.1.0. On a lockfile conflict, take upstream's `Gemfile.lock` and re-run `bundle lock --update brakeman --conservative`. |
| `feature/enforce-authorization` | wip | — (upstream PR not opened yet, by request) | — | `app/controllers/announcements_controller.rb`, `app/controllers/badge_types_controller.rb`, `app/controllers/checkins_controller.rb`, `app/controllers/event_types_controller.rb`, `app/controllers/hooks_controller.rb`, `app/controllers/internal_controller.rb`, `app/controllers/ledger_ownerships_controller.rb`, `app/controllers/ledger_payments_controller.rb`, `app/controllers/people_controller.rb`, `app/controllers/reports_controller.rb`, `app/controllers/team_types_controller.rb`, `app/controllers/teams_controller.rb`, `app/controllers/time_clock_punches_controller.rb`, `app/controllers/tokens_controller.rb`, `app/controllers/variables_controller.rb`, `app/policies/ledger_payment_policy.rb`, `app/policies/team_policy.rb`, `app/policies/time_clock_punch_policy.rb`, `app/policies/token_policy.rb` | — | — | `verify_authorized`/`verify_policy_scoped` on `InternalController`, and `authorize` added wherever it was missing. Fixes real holes: members could delete their team, see its pending applications, and edit or delete its announcements; token update/destroy ignored the edit rule. Has a test that requests every GET page under `InternalController`. Controllers that inherit `ApplicationController` directly (pages, relationships, calendar, search, settings, audit logs, theme, welcome, time kiosk, API) aren't covered. Not in the manifest yet. |
| `feature/calendar-birthday-team-filter` | wip | — (upstream PR not opened yet) | — | `app/controllers/calendar_controller.rb`, `test/controllers/calendar_controller_test.rb` | — | — | Upstream bug: filtering calendar birthdays by team called `.uniq` on the relation (making it an Array), so the next `.where` raised. Filters by id instead. `feature/person-fields` edits neighbouring lines of the same method, so expect a conflict when both are in the manifest; resolve it by rebasing whichever comes later. Not in the manifest yet. |
| `feature/person-fields` | wip | Issue [#489](https://github.com/GatherPack/gatherpack/issues/489) | — | `app/controllers/calendar_controller.rb`, `app/controllers/memberships_controller.rb`, `app/controllers/people_controller.rb`, `app/controllers/relationship_types_controller.rb`, `app/controllers/search_controller.rb`, `app/models/hook.rb`, `app/models/membership.rb`, `app/models/person.rb`, `app/models/relationship.rb`, `app/models/relationship_type.rb`, `app/policies/person_policy.rb`, `app/policies/relationship_policy.rb`, `app/views/hooks/_form.html.erb`, `app/views/people/_form.html.erb`, `app/views/people/index.html.erb`, `app/views/people/relationships.html.erb`, `app/views/people/show.html.erb`, `app/views/relationship_types/_form.html.erb`, `app/views/relationship_types/_relationship_type.html.erb`, `app/views/relationship_types/show.html.erb`, `config/initializers/features.rb`, `config/initializers/filter_parameter_logging.rb`, `config/routes.rb`, `db/schema.rb`, `db/seeds.rb`, `lib/settings.rb`, plus 4 existing test files | `20261002200000_add_guardianship_to_relationship_types.rb`, `20261002200100_create_person_field_groups.rb`, `20261002200200_create_person_fields.rb`, `20261002200300_create_person_field_values.rb`, `20261002200400_create_person_field_badge_grants.rb`, `20261003120000_create_system_person_fields.rb` (the last is a data migration; its `down` deletes only system fields) | `feature_person_fields` (off by default; governs custom fields only) | Spec: `docs/person-fields-spec.md` (§13.3 has implementation notes). Phases 0–2 done: guardianship on relationship types, custom fields with per-field read and write levels and badge grants, setup screens, Preview as…, Member Info roster, hooks, and the seven built-in profile details as system fields. Upgrading keeps today's visibility; "Apply recommended privacy settings" restricts it. Phase 3 (events integration) remains. Not in the manifest yet. |

## Provenance

The fork was reorganized on 2026-10-02. Every commit on the feature branches
above is a patch-identical cherry-pick of the original commit named in its
Notes. The original branches (`fix/audit-log-nil-object-changes` at `dd50a02`,
`search-and-add-screens` at `88546bd`, and `main` at `00bec2c`) are preserved
in `archive/gatherpack-pre-hbr-2026-10-02.bundle` in the workspace parent
folder, with a ref listing alongside it.

Later changes: on 2026-10-02 `feature/membership-filters-fix` gained a new
commit (the name search fix) and moved to the bottom of the search-and-add
chain. The search-and-add commit was replayed on top of it, so its patch now
leaves out the name search line that filters-fix already carries; the
resulting tree is unchanged.

Previously upstreamed work, no longer carried: Resend gateway (PR #485), stale
fixtures (#484), Mission Control auth (#482), blank color crash (#507), manager
person-param scoping (#513).

## Running `bin/fork-rebuild` before branches are pushed

The script reads `origin/` refs by default. To build from local branches, run
`REF_PREFIX= bin/fork-rebuild`. It checks out `hbr/integration` in the current
worktree, so run it from a dedicated integration worktree rather than
`platform/`.
