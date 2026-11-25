# Worker rules (every task)

Read this, then your task brief. The feature spec your brief names is the authority for behavior.

- Read the `gp-map` skill before exploring code. Confirm behavior in the GatherPack source before assuming a Rails convention.
- Feature-branch code is upstream quality: it never mentions HBR, a team name or real people. Sample data and tests use the Northwind made-up people.
- **Add, don't edit:** new files and seams (`Settings.register`, `GatherPack::HookCatalog`, `GatherPack::Features.register` / `register_section`, initializers with `to_prepare`, `Klass.include`). If you must edit an upstream file, list it under "Upstream files touched" in your report.
- **Migrations:** new and reversible; never edit an upstream one. `db/schema.rb` = the base branch's schema + this branch's tables only: migrate against a throwaway DB as the `fork-feature` skill shows, and check `git diff --stat db/schema.rb`.
- **Tests:** your own pair `gp_task_NNN_slug_test` (+ `_versions`); run targeted files with `PARALLEL_WORKERS` ≤ 4 and drop any `_N` copies. Never touch `gatherpack_development`, production, Ditto or `ssh porygon`. Never weaken or delete a test. `bin/rubocop` clean on changed paths.
- **Sample data:** write it to `~/dev/gatherpack/tasks/NNN-sample-data.rb` (the lead commits it on `hbr/platform`), never on the branch. Follow `fork/sample_data/README.md`.
- **Screens:** follow the `fork-spec` skill "Screen design" and the spec's own words-on-screen section. Copy the nearest upstream screen; buttons per gp-map "Views".
- **Feature flags:** behavior changes are gated by the feature's flag (default off).
- **Commits:** upstream message style on your task branch. No `Claude-Session:` trailer (these branches may become upstream PRs); `Co-Authored-By` is fine. You can't push or merge.
- If the brief is ambiguous or needs changes outside its scope, stop and report the question.
- **Final report** (`tasks/NNN-report.md`): what's done, test commands and totals, upstream files touched, anything left.
