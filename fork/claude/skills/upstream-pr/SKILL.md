---
name: upstream-pr
description: Anything outward-facing on GatherPack/gatherpack - issues, PRs, review changes, pitches, fix lists, security disclosures - and retiring a feature after upstream merges it. Use before any gh command against the upstream repo.
---

# Working with upstream

Authority: `fork/STRATEGY.md` "Contributing Upstream", "After upstream merges", "Migrations deployed before acceptance".

## Hard rules

- **Ask first, one question at a time.** Never open an upstream issue or PR (draft or not; drafts are public) without the fork owner's explicit yes for that specific branch and topic. Restate it as one line: "PR for `feature/<x>`: <topic>; drafts are public". A bare "yes" to a multi-part question never covers an outward-facing step.
- **Order of offers:** bug and security fixes, then small seams, then features.
- **Security issues are disclosed privately**, never as public issues or PRs, and never pushed to our public fork before disclosure.
- **Only upstream's own bugs.** Prove each on plain `upstream/main` (with `feature/test-hosts` applied, or upstream's 403s give false passes) and confirm it fails for the same reason as on our build. Name it by where upstream's hole is. Drop anything whose cause is our code.
- **Never rebase or force-push a branch behind an open PR** unless the maintainers ask. Review changes go on as new commits.

## Opening a PR (after the yes)

1. Open (or link) an issue first, framed as a general capability, not an HBR need.
2. Rebase the feature branch onto the latest `upstream/main` (it has no open PR yet), run tests + RuboCop (`gp-test`), push with `--force-with-lease`.
3. `gh pr create -R GatherPack/gatherpack --head frc1747:feature/<name> --base main`, with "Allow edits by maintainers" on.
4. Check the Files changed tab: no `fork/`, `FORK.md`, `bin/fork-*`, `hbr-*` workflows, no "HBR", no deployment references.
5. Set the feature to `proposed` in `FORK.md` with the PR link, and push `FORK.md`.

## Writing for upstream

- Pitches live in `fork/pitches/`. Describe only the feature: summary, problem, what it does, how it's built, adoption options. No status/spec/branch headers, no "we/our", no people's names.
- Features meant for upstream use upstream naming (no `Hbr::`).
- Keep migration filenames stable; ask maintainers not to rename them.

## After upstream merges

Upstream squash-merges, so Git can't match our branch. Confirm the merged version matches what we run, remove the branch from `fork/features.txt` (ask first: manifest change), mark it `retired` in `FORK.md`, rebase dependents onto `upstream/main`, rebuild and test. If our migration already ran in production and theirs differs, add a reconciliation migration.
