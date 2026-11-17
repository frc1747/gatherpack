# NN: <title>

Goal: <one sentence: the behavior that should exist when this is done>

Branch: base `feature/<name>`; work branch `task/NN-slug`; worktree `~/dev/gatherpack/task-NN-slug`
Test DBs: `gp_task_NN_slug_test` (+ `_versions`)

Scope: <files/dirs it may create or change>
Upstream files it may edit: <list, or "none: use seams">
Out of scope: <what not to touch>

Done when:
- <exact test command(s) that must pass, e.g. `bin/rails test test/models/signup_test.rb`>
- `bin/rubocop <changed paths>` clean
- <behavior to verify, with the sample data login to use>

Notes:
- Code pointers: <path:line of the code to start from; saves the worker a search>
- Hooks: <CanBeHooked models / HookCatalog entries this adds, or "none" and why>
- Flag: <feature flag that gates it, or "none">
- Gotchas: <anything from gp-map that applies>
