# BL-081: Tests read the checkout's real settings, and one test depends on row order

| | |
|---|---|
| Kind | fork-only (tests) |
| Priority | medium |
| Status | shipped hbr.53 |
| Added | 2026-11-22 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | `feature/person-fields` (the settings helper); `feature/checklists-connectors` (the rule-order test) |
| Upstream issue / PR | none |

## Summary

Two things make the suite give different answers on different machines:

1. **Settings.** A checkout whose `storage/settings.pstore` has feature flags on (as after loading sample data) fails about 136 tests and 19 errors that pass in CI, where the file doesn't exist. The hbr.52 release run hit this.
2. **Row order.** `test/models/checklist_signup_rule_test.rb:78` failed once in the hbr.52 release CI: the two eligibility messages came back in the other order.

## Evidence

- `lib/settings.rb:169` opens `storage/settings.pstore` in every environment; `test/test_helper.rb` doesn't swap it.
- `test/support/settings_test_helper.rb:15-30`: `with_settings` / `apply_settings` swap in a temporary store only inside the block, and the temporary store starts as a copy of the real one. `test/support/modern_skin_test_settings.rb:19` and `smooth_pages_test_settings.rb:14` copy the real store the same way; `config/initializers/mcp.rb:24` reopens the real path.
- Failing examples with the dev file present: `test/controllers/people_person_fields_test.rb:53`, `test/jobs/form_auto_reminder_job_test.rb:21`, `test/controllers/mcp_controller_test.rb`, `test/models/my_gatherpack/claims_test.rb`, `test/integration/theme_palette_test.rb:22`. With the file moved aside the same 99 tests pass.
- Rule order: `SignupPosition` orders rules by `created_at` (`app/models/signup_position.rb:16`), but the test's `travel_to` (line 9) gives every rule the same time, so Postgres returns ties in any order.

## Fix

- `test_helper.rb`: a global `setup` gives each test an empty temporary PStore (`Settings.instance.store = PStore.new(<tmp path>, true)`), and `teardown` deletes it and puts the original back. An empty store is safe: every setting falls back to its default. Then `SettingsTestHelper.apply` and the modern-skin and smooth-pages helpers copy the current (temporary) store, not the real file.
- `checklist_signup_rule_test.rb`: `travel 1.second` between the rule creates, so their order is the order they were made. The association's `order(:created_at)` stays: ids are UUIDs, so adding `id` wouldn't restore creation order.

## Tests

- With a `storage/settings.pstore` that turns every feature on, the full suite passes.
- No test writes to `storage/settings.pstore` (its mtime is unchanged after a run).

## Fork notes

Test-only changes plus one `order` clause; no upstream files beyond `test/test_helper.rb` if upstream's copy is edited (prefer a `test/support` file required from it, recorded in `FORK.md`).
