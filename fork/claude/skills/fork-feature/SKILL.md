---
name: fork-feature
description: Start, build or extend a GatherPack feature branch in the HBR fork - worktree, manifest, catalog, sample data, FORK.md, flags, migrations, schema hygiene, specs and tests. Use for any code change on a feature/* branch.
---

# Feature branch work

Read `gp-map` first for where things live and which seams exist. Authority: `fork/STRATEGY.md` "Branch Model", "The Feature Manifest", "Minimizing Divergence".

## Start

```bash
cd ~/dev/gatherpack/platform
git fetch upstream origin
git worktree add -b feature/<name> ../feature-<name> upstream/main   # or the dependency branch
```

Existing branch: `git worktree add ../feature-<name> feature/<name>`. Never base on `hbr/integration` or `hbr/platform`.

## Design

- A spec for anything non-trivial goes in `fork/specs/` on hbr/platform. Every spec has a **Hooks** section: which new models `include CanBeHooked`, what `GatherPack::HookCatalog.register_targets/register_events` entries are added, and named domain events, with brief reasons for omissions.
- Generic layers, HBR as configuration: no team-specific words in code. A new use case should be a row in the spec's use-case table, then config or an additive change.
- Add, don't edit: new files, `config/initializers/<feature>.rb` with `to_prepare` registrations, `Klass.include(Module)` patches. Every upstream file still edited goes in `FORK.md` "Upstream files touched".
- Behavior changes get a flag via `GatherPack::Features.register(... default_enabled: false)`; controllers gate with a `before_action`.
- Surface features the way existing ones are surfaced (native cards, profile tabs), not through admin-built widgets.

## Migrations and schema hygiene

- New, reversible migrations only. Never edit an upstream migration.
- `db/schema.rb` on a feature branch = upstream's tables + this branch's own. Dumping from the shared dev DB drags in other features' tables (it blocked hbr.20). Migrate against a throwaway DB loaded from upstream's schema:

```bash
db=gp_<name>_schema
createdb -h localhost -U postgres $db; createdb -h localhost -U postgres ${db}_versions
git show upstream/main:db/schema.rb > db/schema.rb    # or the dependency branch's
DATABASE_URL=postgres://postgres:password@localhost:5432/$db \
VERSIONS_DATABASE_URL=postgres://postgres:password@localhost:5432/${db}_versions \
RAILS_ENV=development bin/rails db:schema:load:primary db:migrate:primary
git diff --stat db/schema.rb    # check the create_table list before committing
```

Dependent branches take a schema fix by merge, not rebase.

## Tests

Delegate runs to the `gp-test` agent (it knows the DB conventions and returns only failures). Each branch has its own test DB, `gp_<name>_test` (+ `_versions`, parallel workers add `_N`); keep them. Match upstream's Minitest and RuboCop style. Never weaken a test to get green.

## Joining the manifest (all on hbr/platform)

Ask before changing the manifest order. A new branch needs, in one session:
1. A line in `fork/features.txt` after its dependencies.
2. An entry in `fork/catalog.yml` (title, emoji, description, audience, settings).
3. `fork/sample_data/features/<name>.rb` (see `fork/sample_data/README.md`). Update it whenever the feature gains a state or a screen.
4. A `FORK.md` row: status, upstream links, depends on, upstream files touched, migrations, flag, notes.

Never commit `HBR-CHANGELOG.md` anywhere but integration. Commit messages follow upstream's style.
