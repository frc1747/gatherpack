# BL-007: First boot on a fresh database crashes in db/seeds.rb

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-05 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/seeds-membership-order` |
| Upstream issue / PR | none yet |

## Summary

On a brand-new install, the web container's first boot fails and Puma never starts. `bin/docker-entrypoint` runs `db:prepare`. On an empty database that loads the schema and then runs `db/seeds.rb`. The seed file gives a person a badge before adding them to the badge's team, and `BadgeAssignment` validates that the person is on that team, so `find_or_create_by!` raises:

```
ActiveRecord::RecordInvalid: Validation failed: Person  must be a member of the badge's team
/rails/db/seeds.rb:63 (our image; line 61 upstream)
Tasks: TOP => db:prepare
```

We hit this on 2026-10-05 when we first started Ditto (our pre-release validation instance) with release `v0.0.0-hbr.6` and an empty database. Production never hit it, because its database already existed, so `db:prepare` only migrates. Upstream has the same code, so every new upstream install hits it.

**Side effects:**

- The container restarts (`restart: unless-stopped`). On the second boot the database exists, so `db:prepare` skips seeding and the app comes up.
- The database is left with partial seed data: everything created before line 61 (Test Team, Test Badge, Test Event, Test Announcement, Test Page, Test Variable, Test Report, Test Hook and 10 Test people), but no memberships or badge assignments.
- With Compose, the `worker` service never starts on the first `up`, because it depends on `web` being healthy. A second `docker compose up -d` fixes it.

## Where things are today (upstream `32e8023`)

- `db/seeds.rb`:
  - Lines 29–30 create "Test Team" and a "Test Badge" belonging to it.
  - Lines 60–63 run the loop:
    ```ruby
    5.times do |time|
      badge_assignment = BadgeAssignment.find_or_create_by!(person: persons[time * 2], badge: badge)
      membership = Membership.find_or_create_by!(team: team, person: persons[time * 2], manager: false)
    end
    ```
- `app/models/badge_assignment.rb`, line 8 has `validate :team_membership`. Lines 16–18 add an error unless `person.all_teams.include?(badge.team)`.
- **History:** the seeds were added in `570c56a` and refined in `4f95286` and `d57b010` (Oct 2024). The validation came later, in `75a06fd` ("148 PR feedback", Brad Thompson, 2024-12-21). Seeds were correct when written, and the new validation broke them. Nothing runs the seeds in CI, so no one noticed (`git grep -n 'load_seed\|db:seed' upstream/main -- test .github bin` is empty).
- `bin/docker-entrypoint`, line 13 runs `./bin/rails db:prepare` on every boot.

## Proposed fix

Swap the two lines, so the membership exists before the badge assignment:

```ruby
5.times do |time|
  Membership.find_or_create_by!(team: team, person: persons[time * 2], manager: false)
  BadgeAssignment.find_or_create_by!(person: persons[time * 2], badge: badge)
end
```

Drop the unused `badge_assignment =` and `membership =` assignments while there (RuboCop's `Lint/UselessAssignment` may flag them). Keep `find_or_create_by!`, so the file stays idempotent as its header comment requires.

**Separate question, not part of the fix:** the seeds create demo records ("Test Team", "Test Hook", "Test Page" and so on) in every environment, including production installs. The header comment says the file should hold "records required to run the application in every environment". Mention it to Brad as a possible follow-up, for example only creating the demo records when `Rails.env.local?`. Don't bundle it into this PR.

## Hooks

No hook changes. The fix only reorders two creates in the seed file. `Membership` and `BadgeAssignment` both `include CanBeHooked`, so their create callbacks fire either way, in the new order. No catalog entries change.

## Tests

- **Regression test:** an integration-style test that runs `Rails.application.load_seed` and asserts it doesn't raise, and that Test Badge has 5 holders who are all members of Test Team. Run it twice to prove it's idempotent. Check that the fixtures don't collide with the seeds' fixed names ("Test Team", "Test Token", `test_variable`). If they do, the test can start by deleting the records it needs to be fresh.
- **Optionally**, add a CI step that runs `bin/rails db:prepare` against an empty database, which also seeds. That catches the next time a validation breaks the seeds. Propose it in the PR description, and let Brad decide whether he wants it in CI.
- **Manual check:** `docker compose up` with an empty database volume. Web becomes healthy on the first boot and the worker starts.

## Fork strategy notes

- This is a generic upstream bug with a two-line fix. Send it upstream as a PR, and don't carry it unless Brad declines.
- No migration and no feature flag.
- Until it's fixed, any fresh install of our releases (a new Ditto, a disaster-recovery rebuild) hits this on first boot. The workaround is to let the container restart once, then run `docker compose up -d` again to start the worker. Ditto was later loaded from a production snapshot, which replaced the partial seed data.

## Draft upstream issue

> **Fresh install fails on first boot: seeds create a badge assignment before the team membership**
>
> On an empty database, `bin/docker-entrypoint` runs `db:prepare`, which loads `db/seeds.rb`. In the loop at the end (lines 60–63), `BadgeAssignment.find_or_create_by!` runs before `Membership.find_or_create_by!` for the same person. Since `BadgeAssignment` validates that the person belongs to the badge's team (added in 75a06fd), the create raises `RecordInvalid: Person must be a member of the badge's team`, `db:prepare` aborts, and Puma never starts. The container comes up on its second boot, because the database then exists and seeding is skipped, but it's left with partial seed data. With Compose, the worker doesn't start on the first `up`, because it waits for web to be healthy.
>
> Fix: create the membership first. Happy to send a PR with a test that runs `load_seed`.
