---
name: fork-sync
description: Weekly HBR fork sync and integration rebuild. Use when asked to sync with upstream, rebase feature branches, rebuild hbr/integration, or when bin/fork-rebuild stops on a conflict.
---

# Fork sync and rebuild

Authority: `fork/STRATEGY.md` "Sync Procedure", "When upstream is broken", "Recurring conflict hotspots" and "Rebuild Script". Read those sections (`sed -n '/^## Sync Procedure/,/^## Continuous Integration/p' fork/STRATEGY.md`) if anything below is unclear or seems out of date.

Work from `~/dev/gatherpack/platform/` for remotes and the manifest; rebase each feature in its own worktree (`~/dev/gatherpack/feature-<name>/`).

## Before you start

```bash
git fetch --multiple upstream origin
git config rerere.enabled true
gh run list -R GatherPack/gatherpack --branch main --event push --limit 3   # upstream CI red? see "Upstream is broken"
gh pr list -R GatherPack/gatherpack --author @me --state open             # these branches are FROZEN
grep -v '^#' fork/features.txt                                            # manifest order
```

## Steps

1. Fast-forward `main` to `upstream/main` and push. If it can't fast-forward, stop and report.
2. Rebase `hbr/platform` onto `upstream/main`.
3. For each manifest branch in order, rebase onto its base (`upstream/main` or its declared dependency in `FORK.md`). Resolve conflicts here, on the feature branch. Run that branch's tests and RuboCop with the `gp-test` agent so the output stays out of your context.
   - **Frozen branches** (open upstream PR): don't rebase, don't push, even with `--force-with-lease`. Let the rebuild merge them as they are. If one conflicts in the rebuild, stop and ask.
4. Check each `proposed` feature for upstream acceptance and update its lifecycle (`FORK.md`).
5. Push rebased branches with `--force-with-lease`.
6. Rebuild: `bin/fork-rebuild` (in `~/dev/gatherpack/integration/`). It stops on the first conflict; fix it on the feature branch (or declare a dependency) and rerun. Never fix it on integration.
7. Full suite + RuboCop on `hbr/integration` (`gp-test`, integration worktree, `PARALLEL_WORKERS=4` on gp-test-pg). Then `git push --force-with-lease origin hbr/integration`.
8. Update `FORK.md` and push it to `hbr/platform` directly (bookkeeping needs no PR).

## Upstream is broken

1. Reproduce each failure on plain `upstream/main` in a detached worktree, so upstream breakage is never mistaken for ours.
2. Fix each on its own small branch from `upstream/main`, written for upstream. Append it to the manifest with a `fork/catalog.yml` entry, a `fork/sample_data/features/<name>.rb` file and a `FORK.md` row naming the upstream commit that broke it. Retire it when upstream fixes it.
3. A feature branch passes when its only failures are the recorded upstream ones.
4. Run the system tests locally (upstream CI has none). After taking upstream's `Gemfile.lock`, check every platform-specific gem still lists a gem for each `PLATFORMS` entry (the `ffi` arm64 break).
5. Don't raise upstream's breakage upstream without asking.

## Conflict recipes

- `db/schema.rb`: never hand-merge. `git show upstream/main:db/schema.rb > db/schema.rb`, then load and migrate on a fresh throwaway DB and commit. The rebuild's `bin/fork-merge-schema` driver handles the `define(version:)` line only. Check that `create_table` = upstream's tables + this branch's own (see `fork-feature` skill, "Schema hygiene").
- `Gemfile.lock`: take upstream's, run `bundle lock`, commit, then do the platform check above.
- Repeated conflicts in routes or shared initializers mean the feature needs a seam or an engine. Say so in `FORK.md` notes.
- Two features conflicting: rebase the later one onto the earlier and declare the dependency, or extract the shared change into its own branch.
