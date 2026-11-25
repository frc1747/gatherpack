# GatherPack Fork Strategy (HBR)

This document explains how the HBR fork of GatherPack is structured, synced, and released, and why. The rules themselves are in [`fork/AGENT.md`](AGENT.md); step-by-step procedures are the skills in `fork/claude/skills/`. When a situation isn't covered, stop and ask rather than improvising a branch or history change.

## Goals

1. Develop features ahead of upstream and offer them back as clean, reviewable PRs.
2. Keep features we need even if upstream declines them, without drifting into an unmaintainable fork.
3. Absorb upstream changes routinely with minimal conflict.
4. Ship one cohesive, tested product built from upstream plus our selected features.

## Remotes

| Remote | Points to | Purpose |
|---|---|---|
| `upstream` | The canonical GatherPack repository | Source of truth for the base product. Read only. |
| `origin` | The HBR fork | Where all of our branches live. |

## Branch Model

| Branch | Base | Who writes to it | Description |
|---|---|---|---|
| `main` | `upstream/main` | Sync script only | An exact mirror of upstream. Never commit here. Always fast-forward only. |
| `hbr/platform` | `upstream/main` | Humans and Claude Code | Fork-only infrastructure: this document, the feature manifest, fork scripts, fork CI workflows, deployment configuration, branding. Nothing that upstream would ever want. |
| `feature/<name>` | `upstream/main` (or a declared dependency) | Humans and Claude Code | One feature per branch. Written to upstream's standards so it can be submitted as a PR unchanged. |
| `hbr/integration` | `upstream/main` | Rebuild script only | Generated. Upstream plus `hbr/platform` plus every active feature, merged in manifest order. Force-pushed on every rebuild. Never commit to it by hand. |

Releases are tags on `hbr/integration`, not a branch. Production deploys only from tags.

One feature per branch has one deliberate exception: `feature/checklists-connectors` and `feature/mcp-checklists-intake` each group thin connector code (checklists with counts, forms, sign-ups and the kiosk; the checklist and intake MCP tools), so we don't carry a branch per connector.

### Why feature branches start from upstream, not from our integration branch

A feature branched from `hbr/integration` silently picks up every other fork feature, which makes it impossible to submit upstream cleanly and impossible to drop later. Branching from `upstream/main` keeps each feature independently reviewable, testable, and removable.

### Dependent features

If feature B genuinely requires feature A (for example, custom fields building on field-level permissions), branch B from `feature/A` and declare the dependency in the manifest. When A is rebased, rebase B onto the new A. When A lands upstream, rebase B onto `upstream/main` and remove the dependency.

## The Feature Manifest

`fork/features.txt` on `hbr/platform` lists the branches merged into `hbr/integration`, one per line, in merge order. Dependencies must appear after the branches they depend on. Lines beginning with `#` are ignored, which is how a feature is temporarily disabled.

A branch joining the manifest needs two more things on `hbr/platform`: an entry in `fork/catalog.yml` (see "The HBR changelog") and a sample data file, `fork/sample_data/features/<name>.rb` (see "Sample data"). When a feature gains a state or a screen, update its sample data in the same work session.

`FORK.md` on `hbr/platform` is the human-readable status register. One row per feature:

| Column | Meaning |
|---|---|
| Branch | `feature/<name>` |
| Status | `wip`, `proposed`, `accepted`, `carried`, `retired` |
| Upstream link | Issue and PR URLs, if any |
| Depends on | Other feature branches |
| Upstream files touched | Every existing upstream file this branch modifies |
| Migrations | Migration filenames the branch adds |
| Flag | The runtime feature flag key, if any |
| Notes | Anything a future maintainer needs |

The "Upstream files touched" column is the single best predictor of future merge pain. Keep it accurate and keep it short.

### Feature lifecycle

1. **wip**: in development on its branch. May or may not be in the manifest.
2. **proposed**: PR opened upstream. Continue carrying it in the manifest.
3. **accepted**: upstream merged it (or an equivalent). On the next sync, verify upstream contains the behavior, remove the branch from the manifest, migrate any data differences, and mark `retired`.
4. **carried**: upstream declined or deferred. We keep it permanently. Refactor it toward the isolation patterns below so it costs as little as possible to maintain.
5. **retired**: no longer merged. Branch kept for history, then deleted after one release cycle.

If upstream accepts a *different* implementation of something we carry, our version is retired in favor of theirs. Write a data migration that moves our records into their structure, gated behind the same release.

## Minimizing Divergence

Every line we change in an upstream file is a line that can conflict forever. Rules, in priority order:

1. **Add, don't edit.** New files (models, controllers, policies, services, views, initializers) never conflict. Prefer them over modifying existing upstream files.
2. **Propose seams before features.** When a feature needs to hook into upstream code, first propose a small, generic extension point upstream (a hook, a configurable callback, a partial slot, a registry). Small seams are far more likely to be accepted than large features, and once a seam exists our feature can live entirely in new files.
3. **Use the existing Hook system and Rails extension mechanisms** (concerns, `ActiveSupport.on_load`, `Module#prepend` in an initializer, view partial overrides) before editing upstream classes directly. Confirm how each mechanism is actually used in the GatherPack source before relying on it. Do not infer Rails conventions.
4. **Carried features graduate to an engine.** A feature with `carried` status should be refactored into `engines/hbr_<feature>/` so it touches as few upstream files as possible, ideally only `Gemfile` and routes.
5. **Namespace only fork-only and carried code** under an `Hbr` module (for example `Hbr::Branding`) and prefix those database tables so they can never collide with upstream names. Features intended for upstream use upstream's naming from the start, so they can be submitted without renaming.
6. **Feature flags for runtime control.** Every fork feature that changes behavior gets a flag stored in the existing PStore-based `Settings` model (GatherPack does not use `credentials.yml.enc`). Default off. This lets one build serve as the product while features are switched on deliberately. Keep flag wiring thin, since upstream may not want the flag and it should be easy to remove before a PR.
7. **Never modify an upstream migration.** Add new migrations only. Keep fork migrations reversible.
8. **Match upstream style.** RuboCop config, Minitest conventions, and commit message style come from upstream. A feature branch should look like upstream wrote it.

## Sync Procedure (weekly, and before every release)

Fast-forward `main`, rebase `hbr/platform`, rebase each manifest branch in order onto its base (resolving conflicts on the feature branch and testing it there), skip branches behind an open upstream PR, check proposed features for acceptance, push with `--force-with-lease`, rebuild, run the full suite on `hbr/integration`, and update `FORK.md`. The exact steps are the `fork-sync` skill. Branches behind an open PR stay on their old base because a force-push puts noise on the public PR even when the code is unchanged. Enable `git rerere` so repeated resolutions replay.

### When upstream is broken

Don't assume `upstream/main` works. `bin/fork-rebuild` always builds on it, so a red upstream can't be skipped by syncing to an older commit. Each upstream failure is reproduced on plain `upstream/main` (so it's never mistaken for ours) and fixed on its own small upstream-ready branch in the manifest, retired when upstream fixes it; a feature branch passes when its only failures are those recorded ones. Upstream CI has no system tests and builds images only after tests pass, so our release check covers both. Procedure: `fork-sync` skill. Example: the 2026-10-23 sync took a red `upstream/main` (ransack 6 and a bundle update) and carried `feature/test-hosts`, `feature/ransack-test-style` and `feature/lockfile-ffi-platforms`.

### Recurring conflict hotspots

- **`db/schema.rb`**: never hand-merge. Take the upstream version, then regenerate by running migrations against a fresh database and commit the result. One conflict is routine and resolved automatically: two branches that both add migrations disagree only on the `define(version: ...)` line. A second is resolved too: two independent branches that add whole tables, foreign keys or columns at the same place and change nothing the common base had there; both sets are kept (tables and keys sorted, columns in merge order). A table both sides changed, or any partial block, still stops the rebuild. `bin/fork-rebuild` registers `bin/fork-merge-schema` as a git merge driver for `db/schema.rb` (in the repository's own config and `info/attributes`, so no tracked file changes); it keeps the newer version and leaves any other schema conflict in place, so the rebuild still stops on it. The integration CI job's `db:migrate` from an empty database is the check that the merged schema is right.
- **`Gemfile.lock`**: never hand-merge. Take the upstream version, then run `bundle lock` (or `bundle install`) and commit the result. Then check that platform-specific gems still list a gem for every platform under `PLATFORMS`: upstream's lockfile has lost them before (`ffi`, 2026-10-23), which breaks only the arm64 image build.
- **Routes and shared initializers**: if these conflict repeatedly, that is a signal the feature needs a seam or an engine.

## Rebuild Script

`bin/fork-rebuild` on `hbr/platform` regenerates the integration branch deterministically: it checks out `upstream/main`, merges `hbr/platform`, then merges each manifest branch in order with `--no-ff`, aborting on the first conflict. Read the script for the current behavior.

The script refuses to resolve conflicts itself on purpose. The one exception is the schema version line, which `bin/fork-merge-schema` resolves (see "Recurring conflict hotspots"). If two features conflict with each other, resolve it by rebasing the later branch onto the earlier one and declaring the dependency, or by extracting the shared change into its own small branch that both depend on.

### Replaced templates

A feature can replace a template through the view override seam: a file at `app/view_overrides/<key>/<path>` replaces `app/views/<path>` while that feature is active. The replacement doesn't pick up later changes to its original. After the changelog commit, `bin/fork-rebuild` runs `bin/fork-override-check`, which compares each original on the new build against `fork/view-overrides.lock` and prints any that changed, with the diff. It only warns: it never stops the rebuild and changes nothing in the build. After reviewing a change and updating the replacement if needed, run `bin/fork-override-check --ref origin/hbr/integration --accept <override path>` in `platform/` and commit the lock. Tests: `ruby test/fork/fork_override_check_test.rb` (no database needed).

### The HBR changelog

After the last merge, `bin/fork-rebuild` runs `bin/fork-changelog`, which writes `HBR-CHANGELOG.md` at the root of the integration branch, and commits it as `Update HBR changelog`. That generated commit is the only commit on `hbr/integration` that isn't a merge; the script makes it, so the script is still the only writer of the branch. The file is a catalog of the build: the release it will be, the upstream base, a Mermaid diagram of the merge order and dependencies, one card per manifest feature, what's new since the previous `v*-hbr.*` tag, and the disabled and retired features.

- **Inputs.** The manifest, `fork/catalog.yml` and `FORK.md` are read from the platform ref the rebuild used. Status, shipped release, upstream links and dependencies come from `FORK.md`; branch heads and migrations come from the build's merges. `fork/catalog.yml` holds the plain-language part (title, emoji, description, audience, settings), keyed by branch. Add an entry when a branch joins the manifest. A branch without one still builds, with a "No description yet" marker and a warning.
- **Deterministic.** Every commit the rebuild makes is dated with the newest commit date among its inputs (`upstream/main`, the platform ref and every manifest branch), not the clock. The same inputs give the same commits and a byte-identical changelog. Release tags are inputs too: once the build is tagged, regenerating it names that tag as its release. A plain rebuild describes an untagged build as "`v…-hbr.<n>` when tagged"; a release rebuild (`bin/fork-rebuild --release <tag>`) writes the tag it is about to get, so the tagged file never says "not tagged yet".
- **Only on `hbr/integration`.** Never commit `HBR-CHANGELOG.md` to `hbr/platform` or a feature branch; it could then conflict in the rebuild. `bin/fork-changelog` refuses to run if any input branch carries it.
- **Failure stops the rebuild.** If generation fails, the script exits non-zero after the merges, leaving the branch without its changelog commit. Fix the cause and rebuild; don't push that branch.

To preview the file for a build without rebuilding, run `bin/fork-changelog --stdout` in a checkout of that build (for example a detached worktree of `origin/hbr/integration`). Tests: `ruby test/fork/fork_changelog_test.rb` (no database needed).

After a successful rebuild and passing tests, push with `git push --force-with-lease origin hbr/integration`.

### Sample data

`bin/rails hbr:sample_data` loads the Northwind sample organization into any build, with data for every feature in its manifest, dated relative to the moment it's loaded. It lives on `hbr/platform` (`fork/sample_data/`, `lib/tasks/hbr_sample_data.rake`), so every integration build and release image carries it. [`fork/sample_data/README.md`](sample_data/README.md) says how to load it, lists the logins, and shows how to add a feature's data; the design is `fork/specs/sample-data-spec.md`.

- **One file per manifest branch.** A branch with no file is a warning in the rebuild and the changelog, and a failure in the integration CI job.
- **Test copies only.** It refuses a database with real logins or people unless forced.
- Tests: `ruby test/fork/sample_data_test.rb` (no database needed); CI loads it twice into the freshly migrated database.

## Continuous Integration

GitHub Actions workflows live on `hbr/platform` (so they ride along into integration). Set the fork's default branch on GitHub to `hbr/platform`. Actions reads workflow files from the pushed branch for push events, and feature branches deliberately don't contain fork workflows, so feature-branch checks must run as scheduled or manually triggered jobs from the default branch that check out each feature branch explicitly. Name fork workflow files `hbr-*.yml`.

The workflows should cover:

1. **Each feature branch alone against `upstream/main`.** Proves the feature is upstreamable and self-contained.
2. **`hbr/integration`.** Proves the combination is cohesive. Full test suite, RuboCop, `db:migrate` from an empty database, and loading the sample data into it twice.
3. **Scheduled upstream drift check.** Daily job that fetches upstream, attempts the rebuild, and opens an issue if any feature fails to merge or tests break. This surfaces trouble when it's one commit old instead of fifty. It should also report upstream's own CI result on `main`, so a red upstream shows up the day it happens (BL-025, not built yet).

## Releases and Deployment

1. Tag releases on `hbr/integration` as `v<upstream-version>-hbr.<n>` (for example `v1.8.0-hbr.3`), so it's always obvious which upstream version a release is based on.
2. Generate release notes listing the upstream base commit and every feature branch and head commit included. `HBR-CHANGELOG.md` on the tagged commit has all of these (see "The HBR changelog"); its "What's new" section is the starting point for the notes. Cut the release with `bin/fork-rebuild --release v<upstream-version>-hbr.<n>`, push it, let CI pass, then tag the rebuild's last commit, the changelog commit, with exactly that name, so the file in the release names itself and its own image. The script refuses a tag that already exists on another build or doesn't come after the latest release.
3. Deploy only from tags. Rollback means redeploying the previous tag.
4. Before tagging, confirm migrations run cleanly from the previous release's database state, not just from empty.

Procedure: `fork-release` skill. The private release flow used for `hbr.24` to `hbr.33` ended with `hbr.34`; every release is now a public tag and ghcr image.

## Contributing Upstream

Fork tooling (`FORK.md`, `fork/`, `bin/fork-*`, `.github/workflows/hbr-*.yml`) exists only on `hbr/platform` and never appears in a feature branch, so upstream PRs contain only the feature itself. The steps (issue first, rebase, cross-fork PR, review changes as new commits) are the `upstream-pr` skill; nothing goes upstream without the fork owner's yes.

1. If a feature is too large to be accepted, split it: propose the seam first, keep the HBR-specific behavior as a carried feature on top of it.
2. Offer in this order: fixes for upstream bugs and security issues, then small general seams (extension registries, profile tabs, the Ransack `auth_object`), then features. A large feature stays portable as long as the seams it needs are upstream; the dependent stacks (person-fields, then forms; extension-registries, then sign-ups) have to be accepted in order.
3. Upstream doesn't always stop on a red `main`. If it's red when a PR is opened, say so in the PR and name the failures that aren't ours. After a merge, check that upstream's version matches what we run before retiring the branch.

### After upstream merges

Upstream will likely squash-merge, producing a commit Git can't match to our branch. Leaving the branch in the manifest will cause conflicts or duplicate code. Retire it explicitly: confirm the merged version matches what we run, remove it from `fork/features.txt`, mark it `retired` in `FORK.md`, rebase any dependent branches onto `upstream/main`, then rebuild and test.

### Migrations deployed before acceptance

If a feature ran in production before upstream merged it, our migration is already recorded in `schema_migrations`. Ask maintainers to keep the migration filename unchanged. If they rename it or change the schema during review, add a one-time reconciliation migration in the fork that aligns our schema with theirs and marks their version as applied. Where timing allows, keep upstream-bound features out of production until upstream decides.

## Agent setup

The rules for Claude Code are in [`fork/AGENT.md`](AGENT.md), which the workspace `CLAUDE.md` imports so every session starts small. Procedures are skills and agents in `fork/claude/`, linked into the workspace's `.claude/` and loaded only when a task needs them; parallel workers follow `fork/claude/worker-rules.md`. Skills that hold deployment details (hosts, containers, credentials, production data) stay in the workspace's `.claude/skills/` only and are never committed, because this repository is public.

## Local Workspace Layout

One parent folder holds a worktree per branch and a `CLAUDE.md` that isn't in any repository (Claude Code reads `CLAUDE.md` from parent directories, so it applies to every branch):

```text
gatherpack/
  CLAUDE.md      # imports platform/fork/AGENT.md
  .claude/       # skills/ and agents/: symlinks to platform/fork/claude/*, plus local-only skills
  platform/      # hbr/platform, the primary clone
  integration/
  feature-<name>/
  tasks/         # briefs for dispatched work; never committed
```

Link the skills once from the parent folder, and into each new worktree (Claude Code finds skills at the git root):

```bash
mkdir -p .claude/skills .claude/agents
for d in platform/fork/claude/skills/*/; do ln -sfn "../../${d%/}" .claude/skills/; done
for f in platform/fork/claude/agents/*.md; do ln -sfn "../../$f" .claude/agents/; done
printf '/.claude/skills\n/.claude/agents\n' >> "$(git -C platform rev-parse --path-format=absolute --git-common-dir)/info/exclude"
# per worktree:
mkdir -p <worktree>/.claude && ln -sfn ../../.claude/skills <worktree>/.claude/skills && ln -sfn ../../.claude/agents <worktree>/.claude/agents
```
