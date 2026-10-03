# GatherPack Fork Strategy (HBR)

This document defines how the HBR fork of GatherPack is structured, synced, and released. Follow it exactly. When a situation isn't covered here, stop and ask rather than improvising a branch or history change.

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

### Why feature branches start from upstream, not from our integration branch

A feature branched from `hbr/integration` silently picks up every other fork feature, which makes it impossible to submit upstream cleanly and impossible to drop later. Branching from `upstream/main` keeps each feature independently reviewable, testable, and removable.

### Dependent features

If feature B genuinely requires feature A (for example, custom fields building on field-level permissions), branch B from `feature/A` and declare the dependency in the manifest. When A is rebased, rebase B onto the new A. When A lands upstream, rebase B onto `upstream/main` and remove the dependency.

## The Feature Manifest

`fork/features.txt` on `hbr/platform` lists the branches merged into `hbr/integration`, one per line, in merge order. Dependencies must appear after the branches they depend on. Lines beginning with `#` are ignored, which is how a feature is temporarily disabled.

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

1. `git fetch upstream origin`
2. Fast-forward `main` to `upstream/main` and push. If it can't fast-forward, someone committed to `main`. Stop and report.
3. Rebase `hbr/platform` onto `upstream/main`.
4. For each branch in the manifest, in order, rebase onto its base (`upstream/main` or its declared dependency). Resolve conflicts *on the feature branch*, where the context is clearest, not later during integration. Run that branch's tests and RuboCop after each rebase.
5. Check each `proposed` feature for upstream acceptance and update the lifecycle.
6. Force-push rebased feature branches with `--force-with-lease`.
7. Run `bin/fork-rebuild` to regenerate `hbr/integration`.
8. Run the full test suite and RuboCop on `hbr/integration`.
9. Update `FORK.md` with anything that changed.

Enable `git rerere` (`git config rerere.enabled true`) so repeated conflict resolutions are recorded and replayed.

### Recurring conflict hotspots

- **`db/schema.rb`**: never hand-merge. Take the upstream version, then regenerate by running migrations against a fresh database and commit the result. One conflict is routine and resolved automatically: two branches that both add migrations disagree only on the `define(version: ...)` line. `bin/fork-rebuild` registers `bin/fork-merge-schema` as a git merge driver for `db/schema.rb` (in the repository's own config and `info/attributes`, so no tracked file changes); it keeps the newer version and leaves any other schema conflict in place, so the rebuild still stops on it. The integration CI job's `db:migrate` from an empty database is the check that the merged schema is right.
- **`Gemfile.lock`**: never hand-merge. Take the upstream version, then run `bundle lock` (or `bundle install`) and commit the result.
- **Routes and shared initializers**: if these conflict repeatedly, that is a signal the feature needs a seam or an engine.

## Rebuild Script

`bin/fork-rebuild` on `hbr/platform` regenerates the integration branch deterministically. Reference implementation:

```bash
#!/usr/bin/env bash
set -euo pipefail

INTEGRATION="hbr/integration"
PLATFORM="origin/hbr/platform"
MANIFEST_PATH="fork/features.txt"

git fetch upstream
git fetch origin

manifest="$(git show "${PLATFORM}:${MANIFEST_PATH}")"

git checkout -B "${INTEGRATION}" upstream/main
git merge --no-ff --no-edit -m "Integrate hbr/platform" "${PLATFORM}"

while IFS= read -r branch; do
  branch="${branch%%#*}"
  branch="$(echo "${branch}" | xargs)"
  [[ -z "${branch}" ]] && continue
  echo "Merging ${branch}"
  if ! git merge --no-ff --no-edit -m "Integrate ${branch}" "origin/${branch}"; then
    echo "Conflict merging ${branch}. Resolve it on the feature branch, not here." >&2
    git merge --abort
    exit 1
  fi
done <<< "${manifest}"

echo "Integration branch rebuilt from upstream/main at $(git rev-parse --short upstream/main)"
```

The script refuses to resolve conflicts itself on purpose. The one exception is the schema version line, which `bin/fork-merge-schema` resolves (see "Recurring conflict hotspots"); the reference implementation above predates it. If two features conflict with each other, resolve it by rebasing the later branch onto the earlier one and declaring the dependency, or by extracting the shared change into its own small branch that both depend on.

After a successful rebuild and passing tests, push with `git push --force-with-lease origin hbr/integration`.

## Continuous Integration

GitHub Actions workflows live on `hbr/platform` (so they ride along into integration). Set the fork's default branch on GitHub to `hbr/platform`. Actions reads workflow files from the pushed branch for push events, and feature branches deliberately don't contain fork workflows, so feature-branch checks must run as scheduled or manually triggered jobs from the default branch that check out each feature branch explicitly. Name fork workflow files `hbr-*.yml`.

The workflows should cover:

1. **Each feature branch alone against `upstream/main`.** Proves the feature is upstreamable and self-contained.
2. **`hbr/integration`.** Proves the combination is cohesive. Full test suite, RuboCop, and `db:migrate` from an empty database.
3. **Scheduled upstream drift check.** Daily job that fetches upstream, attempts the rebuild, and opens an issue if any feature fails to merge or tests break. This surfaces trouble when it's one commit old instead of fifty.

## Releases and Deployment

1. Tag releases on `hbr/integration` as `v<upstream-version>-hbr.<n>` (for example `v1.8.0-hbr.3`), so it's always obvious which upstream version a release is based on.
2. Generate release notes listing the upstream base commit and every feature branch and head commit included.
3. Deploy only from tags. Rollback means redeploying the previous tag.
4. Before tagging, confirm migrations run cleanly from the previous release's database state, not just from empty.

## Contributing Upstream

Fork tooling (`FORK.md`, `fork/`, `bin/fork-*`, `.github/workflows/hbr-*.yml`) exists only on `hbr/platform` and never appears in a feature branch, so upstream PRs contain only the feature itself.

1. Open an issue upstream describing the need before the PR. Keep it brief and framed as a general capability, not an HBR-specific requirement. Wait for a signal that maintainers want it before polishing.
2. Rebase the feature branch onto the latest `upstream/main`, run tests and RuboCop, and push.
3. Open a cross-fork PR from `origin:feature/<name>` into `upstream:main`. Check "Allow edits by maintainers." Before submitting, confirm the "Files changed" tab contains no fork tooling and no references to HBR or our deployment.
4. Make all review changes on the same feature branch. The PR and the next rebuild both pick them up. If maintainers prefer no force-pushes during review, add fixup commits and rebase only when asked.
5. If a feature is too large to be accepted, split it: propose the seam first, keep the HBR-specific behavior as a carried feature on top of it.

### After upstream merges

Upstream will likely squash-merge, producing a commit Git can't match to our branch. Leaving the branch in the manifest will cause conflicts or duplicate code. Retire it explicitly: confirm the merged version matches what we run, remove it from `fork/features.txt`, mark it `retired` in `FORK.md`, rebase any dependent branches onto `upstream/main`, then rebuild and test.

### Migrations deployed before acceptance

If a feature ran in production before upstream merged it, our migration is already recorded in `schema_migrations`. Ask maintainers to keep the migration filename unchanged. If they rename it or change the schema during review, add a one-time reconciliation migration in the fork that aligns our schema with theirs and marks their version as applied. Where timing allows, keep upstream-bound features out of production until upstream decides.

## Rules for Claude Code

1. Never commit to `main` or `hbr/integration`.
2. Never branch a feature from `hbr/integration` or `hbr/platform`.
3. One feature per branch. If a change serves two features, it's a third branch.
4. Resolve conflicts on feature branches, never during the integration merge.
5. Use `--force-with-lease`, never plain `--force`.
6. Keep `FORK.md` current in the same work session as any feature status change.
7. Before modifying any existing upstream file, check whether a seam, hook, new file, or engine could achieve the same result. If you still need to edit it, record the file in `FORK.md`.
8. Confirm behavior against actual GatherPack source before assuming a Rails convention or API.
9. Ask before deleting any branch, rewriting any tag, or changing the manifest order.

## Local Workspace Layout

This document lives at `fork/STRATEGY.md` on `hbr/platform` only, so it is absent from feature branch checkouts. To keep it loaded in every session, use one parent folder containing a worktree per branch, with a `CLAUDE.md` in the parent folder (not in any repository) that imports the strategy from the platform worktree. Claude Code reads `CLAUDE.md` files from parent directories, so this applies regardless of which branch is being worked on.

```text
gatherpack/
  CLAUDE.md
  platform/
  feature-field-permissions/
  feature-resend/
```

`gatherpack/CLAUDE.md`:

```markdown
@platform/fork/STRATEGY.md
```

`platform/` is the primary clone, permanently checked out on `hbr/platform`. Each feature gets its own worktree, created from inside `platform/`:

```bash
git worktree add ../feature-resend feature/resend
```

Do all feature work in that feature's worktree. Remove a worktree with `git worktree remove` once its feature is retired.

## Initial Setup Tasks

1. Add the `upstream` remote and verify `main` matches `upstream/main` exactly. If the fork's `main` already has our commits on it, move them to feature branches and reset `main` to upstream.
2. Create `hbr/platform` from `upstream/main` with this document saved as `fork/STRATEGY.md`, plus `FORK.md`, an empty `fork/features.txt`, and `bin/fork-rebuild`.
3. Set up the local workspace layout described in "Local Workspace Layout."
4. Inventory existing fork work (for example the Resend email gateway and field-level permissions) and split it into `feature/*` branches based on `upstream/main`, recording each in `FORK.md`.
5. Add the CI workflows described above.
6. Run the first rebuild, run the suite, and cut the first `-hbr.1` tag once it's green.
7. Set the fork's default branch to `hbr/platform`, and enable branch protection on `main` (no direct pushes) and on `hbr/platform` (PR required).
