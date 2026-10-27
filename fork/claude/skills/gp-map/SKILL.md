---
name: gp-map
description: Map of the GatherPack codebase (HBR fork) - domain models, permissions, settings, feature flags, hooks, extension registries, fork features, tests and gotchas. Read before exploring or changing GatherPack code, instead of grepping from scratch.
---

# GatherPack code map

Paths are relative to a checkout (`~/dev/gatherpack/integration` has everything merged). Upstream's `AGENTS.md` (repo root) covers the stack, data model overview and dev commands; read it for those. This page covers what it doesn't. Mapped 2026-10-27 at integration `321bed7`; if something here doesn't match the code, trust the code and fix this page.

## Stack in one line

Rails 8.1, Postgres (UUID PKs), Pundit, Devise + omniauth, PaperTrail in a **separate `versions` DB**, `neat_ids`, Ransack, Hotwire + importmap (no JS bundler; yarn only builds CSS), Bootstrap 5.3, SolidQueue (no Redis), Minitest with fixtures.

## Domain essentials (app/models)

- **IDs**: UUID in the DB, public `neat_id` with a prefix per model (`per_` Person, `tm_` Team, `usr_` User, `bdg_` Badge, `evt_` Event, `cki_` Checkin, `pg_` Page, `rety_` RelationshipType...). `NeatIds.find(id)`; `ApplicationRecord#method_missing` adds `foo_nid`/`foo_nids` accessors. Never change the salt or a table name.
- **Person** is the hub; **User** is login only (`admin`, `architect` are separate flags; admin does not imply architect). Permission helpers on Person: `admin?`, `manager?` (manager of *any* team; check `all_managed_teams` for a specific one), `all_teams`/`all_team_ids`, `all_managed_teams`, `all_managed_people`, `can_manage(person)`, `guardians`, `wards`, `relatives`.
- **Team** hierarchy is `parent_id`; ancestors/descendants recurse in Ruby (N+1, no SQL). Avoid in loops. **Membership** carries `manager: true`; managers also manage descendant teams.
- **Badge/BadgeAssignment**: a team badge requires the person in `person.all_teams`. **Relationship** (parent/child Person + RelationshipType with `guardianship` none/minor/consented).
- **Event/EventType/Checkin**, **TimeClockPeriod/TimeClockPunch** (`end_time nil` = clocked in).
- Validations on Relationship, Checkin, TimeClockPunch need the `created_by` attr set (controllers do it; scripts must too).
- **Custom fields** (fork, person-fields): `PersonField*`; `person.readable_fields_for(viewer)`, `writable_fields_for`, `assign_field_values(values, acting:)`; `field_value`/`set_field_value` skip viewer checks.

## Authorization

- Pundit. `ApplicationPolicy` defaults **every action to true**: a policy that forgets `update?`/`destroy?` is open. No global `verify_authorized`.
- Controller pattern: `@x = authorize policy_scope(Model).find(params[:id])`; index uses `policy_scope(Model).ransack(params[:q])`.
- `AdminPolicy`/`ArchitectPolicy` bases; `ReportPolicy`: run = admin, author = architect.
- **Gotcha**: `EventPolicy::Scope` and `PagePolicy::Scope` use `team_id: ""` on a uuid column, which becomes `= NULL` and matches nothing. Non-admins never see team-less events. Scripts that create events must set `team_id`.
- Ransack: models allowlist `ransackable_attributes`; associations default to `[]`.

## Executable content

- Dynamic **Pages** (`pages_helper#format_page_content`): `ERB.new(content).result(binding)` in the view context (all helpers, `current_user`, models). Only admins can author (`editor == "admin"` enforced). Runtime errors give a 500.
- **Widgets** (fork) render ERB the same way. **Reports**: `eval(code)` in the controller. **Hooks**: `eval(code)` with `model` in scope. **Variables**: `Variable.find_by(name:).value` (typed KV).
- HBR's report pages are Page sources kept in `~/dev/gatherpack/pages/*.html.erb`; shared print CSS is the Variable `report_print_css`.

## Seams: how fork features plug in

Everything goes in `config/initializers/<feature>.rb` inside `Rails.application.config.to_prepare do ... end`:

- **Feature + flag**: `GatherPack::Features.register(GatherPack::Feature.new(key:, label:, description:, default_enabled: false, nav_section:, nav_items: [NavItem.new(label:, path:, icon:)], setup_items:, profile_tabs: [ProfileTab.new(label:, path: ->(person){}, visible: ->(user, person){})]))` (`lib/gatherpack/feature{,s}.rb`). A toggleable feature auto-creates setting `feature_<key>`. `Features.enabled?(:key)`. Gate controllers with a `before_action` that redirects when off (`forms_controller.rb`).
- **Settings**: `Settings.register(key, type, name, default_string, group, description)` (`lib/settings.rb`, PStore at `storage/settings.pstore`). `Settings[:key]`. Booleans are stored as strings. Values are **cached per process**: a change made by `rails runner` needs a web/worker restart to show.
- **Hooks**: `include CanBeHooked` fires `"<table> - create/update/destroy"`; register with `GatherPack::HookCatalog.register_targets(...)` / `register_events("x - y")`; fire custom events with `Hook.where(event: "x - y").each { |h| h.run(self) }` (see `Signup#run_status_hooks`).
- **Patching upstream classes without editing them**: `Checkin.include(Signups::CheckinFulfilment)`, `Badge.has_many ...`, `SignupsController.before_action { }` in `to_prepare`.
- **Feature registries**: `Commitments.register_source(kind, klass)` (credit sources); `Signups.extensions.register_sheet_panel(key, partial:)` and `register_on_behalf_of_hint`.
- **Notifications**: `ActiveSupport::Notifications` `person_field_changed.gatherpack` (forms resync).
- **No seam yet** for routes (edit `config/routes.rb`; `routes_proc` exists but its loop is commented out), dashboard cards (edit `app/views/welcome/dashboard.html.erb`) or recurring jobs (`config/recurring.yml`).
- **Gateways**: STI `Gateway`, subclasses call `Gateway.register(self, :email_sending|:email_receiving|:payment)`; `Gateway[:email_sending]`.
- **Jobs**: SolidQueue; recurring in `config/recurring.yml`; app jobs in `app/jobs/` (`FormScheduleJob`, `SignupReminderJob.schedule_for(...)`).

## Fork features (by initializer)

| Feature | Flag | Where |
|---|---|---|
| person-fields | `feature_person_fields` | `app/models/person_field*.rb`; touches ~40 upstream files (the divergence point) |
| forms | `feature_forms` | `app/models/form*.rb`, `config/initializers/forms.rb`; settings `forms_creator_badge`, `forms_creator_highest_team` |
| signups | `feature_signups` | `app/models/signup*.rb`, `app/models/signups/`, `config/initializers/signups.rb` |
| commitments | `feature_commitments` | `app/models/commitment*.rb`, `app/models/commitments/`, `config/initializers/commitments.rb` |
| signup-credit | (signups + commitments) | `Commitments::Signup*Source`, `config/initializers/signup_credit.rb` |
| profile tabs | registry | `people_helper#feature_profile_tabs`, `people/_show_shared.html.erb`; `config/initializers/commitments_profile_tab.rb` |
| widgets | `feature_widgets` | `app/models/widget.rb` (fork-only, never upstream) |
| kiosk | `:time_tracking` | `app/models/time_kiosk*`, `time_kiosk_controller`, `layouts/kiosk.html.erb` |
| app-version | none | `version_helper.rb` (`GATHERPACK_VERSION`) |

Manifest order and status: `fork/features.txt`, `FORK.md`.

## Views

`layouts/application.html.erb` renders `_navbar` and `_sidebar` (the sidebar comes from the Features registry: sections People 10, Time 20, Finance 30, Communication 40, Content 50). Dashboard: `welcome#index` with `welcome/dashboard.html.erb`. Search-and-add UI: `shared/_add_panel`, `_add_candidate(s)`.

## Tests

- Minitest, fixtures (`fixtures :all`, 46 YAML files), no FactoryBot. Fork tests build data with world helpers in `test/support/*_world.rb` (`build_commitments_world`, `create_world_person`, `with_feature`).
- Settings in tests: `with_settings(key: val) { }` (`test/support/settings_test_helper.rb`) swaps in a temp PStore.
- Sign in: `include Devise::Test::IntegrationHelpers`; `sign_in user`.
- Two DBs per env (primary + `versions`). Rails reads `DATABASE_URL` and `VERSIONS_DATABASE_URL` from the env (the `<name>_DATABASE_URL` convention); the repo itself only sets `DATABASE_HOST/USERNAME/PASSWORD`.
- `bin/rails db:test:prepare`, `bin/rails test [file[:line]]`, `bin/rails test:system` (headless Chrome), `bin/rubocop` (omakase), `bin/brakeman --no-pager`. Many system test files are empty stubs.
- Fork tooling tests: `ruby test/fork/fork_changelog_test.rb`, `ruby test/fork/sample_data_test.rb` (no DB).
- Use the `gp-test` agent to run anything long.

## Gotchas (collected)

- Default-true policies; `team_id: ""` scopes; `created_by` attrs; Team recursion cost.
- Migrations must run for both DBs: `db:migrate:primary` and `db:migrate:versions`. `db:migrate` alone only hits primary.
- `db/seeds.rb` crashes on an empty DB (BL-007): load the schema first, then `hbr:sample_data`.
- Loading sample data writes the checkout's `storage/settings.pstore`; back it up first.
- `Variable#value` has a dead `nil if raw_value.blank?` line.
- PaperTrail whodunnit is `true_user` (the real admin under impersonation). Scripts set `PaperTrail.request.whodunnit` themselves.
