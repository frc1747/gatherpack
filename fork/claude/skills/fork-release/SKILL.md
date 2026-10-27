---
name: fork-release
description: Cut, verify and stage an HBR release (v<upstream>-hbr.<n> tag on hbr/integration, ghcr image). Use when asked to release, tag, cut hbr.<n>, or prepare a build for Ditto or production.
---

# Releasing an HBR build

Authority: `fork/STRATEGY.md` "Releases and Deployment" and "The HBR changelog". Deploy steps on Ditto/Porygon are in the local `prod-ops` skill.

## Cut it

1. Sync first if upstream moved (`fork-sync` skill). Every manifest branch has a `fork/catalog.yml` entry and a sample data file, or the rebuild warns and CI fails.
2. Pick the tag: next `n` after the latest `git tag -l 'v*-hbr.*' --sort=-v:refname | head -1`.
3. In `~/dev/gatherpack/integration/`: `bin/fork-rebuild --release v<upstream>-hbr.<n>`. The script refuses a tag that exists on another build or doesn't come after the latest release.
4. Preview the changelog if needed: `bin/fork-changelog --stdout`. Its "What's new" section is the start of the release notes.
5. Full suite + RuboCop + system tests (`gp-test` agent). Then `git push --force-with-lease origin hbr/integration` and wait for the HBR Integration workflow (`gh run list --workflow hbr-integration.yml --limit 1`).
6. Tag the rebuild's last commit, the "Update HBR changelog" commit, with exactly that name. Use an annotated tag with a message modeled on the previous one (`git tag -n20 <previous>`). Push the tag. Never `v*` for anything but a release: it triggers an image publish. Upstream-candidate checkpoints use `upstream-candidate/<feature>-<n>`.
7. Check that the image build passes for amd64 and arm64 (`gh run list --workflow build.yml --limit 1`).

## Before it goes to production

- Migrations must run cleanly from the previous release's database state, not just from empty: restore a fresh production snapshot into a throwaway DB, migrate, then delete the snapshot (it holds PII).
- Compare the release with what production runs; list the migrations and settings changes the operator must know about.
- Ditto gets the release first (`prod-ops` skill). Production switches only when the fork owner changes `GATHERPACK_TAG` themselves.

## After

Record the release in `FORK.md` (shipped release per feature) and push it to `hbr/platform` directly.
