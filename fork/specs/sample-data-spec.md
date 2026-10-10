# Spec: Sample data in every build

Status: draft rev. 1, 2026-10-10. Not started.

This spec lives on `hbr/platform`. Everything it adds is fork tooling and stays on `hbr/platform`; no feature branch and no upstream file changes.

## 1. Goal

Anyone who checks out or pulls a tagged release can load one set of sample data, the Northwind Community, with one command. That data always exercises every feature in that build: forms with future due dates, custom fields at several read levels, a guardian, widgets, kiosk cards and periods, and so on.

1. **One command**, from a checkout or from the published image.
2. **Matches the build.** It loads data only for the features merged into that build.
3. **Always current.** Every date is relative to the moment it's loaded, so a release loaded months later still has upcoming events, open forms and a current time clock period.
4. **Kept complete.** A branch can't join the manifest without its sample data, and CI loads the data on every integration build.
5. **Documented.** A README explains how to load it, and the changelog points to it (§8).

### 1.1 Non-goals

- Anything for production. The loader refuses to run on a database with real data (§6).
- Replacing `db/seeds.rb`. That's upstream's file; this spec leaves it alone. BL-007 (seeds crash on a fresh database) is separate.
- Realistic volume for performance testing. About 30 people, as today.
- Screenshots or a demo script. The README lists what to try, not a tour.

## 2. What exists today

| Piece | Where | Use here |
|---|---|---|
| Northwind script | `~/dev/gatherpack-dev-data/populate_dev.rb` (outside every repo) | Becomes the base layer (§4). Its names and keys are kept, so existing dev databases update in place. Its fixed 2026 dates become relative |
| Its README | `~/dev/gatherpack-dev-data/README.md` | The logins, team tree and card numbers move into the new README (§8) |
| `db/seeds.rb` | upstream, edited by `feature/person-fields` (`PersonField.ensure_system_fields!`) | Runs on `db:prepare` against an empty database. Creates "Test …" records. The loader coexists with them |
| `bin/docker-entrypoint` | upstream | Runs `db:prepare` when the web container starts the server |
| The image | `Dockerfile` `COPY . .`, `.dockerignore` | `fork/` is not ignored, so a tagged image already contains everything on `hbr/platform` |
| Feature flags | `GatherPack::Feature#enabled?` reads `Settings[:"feature_#{key}"]` | The loader turns on the flags for features in the build |
| Settings cache | BL-013: values cached per process | The running app sees flag changes only after a restart. The README says so |
| Catalog check | `bin/fork-changelog` warns when a manifest branch has no `fork/catalog.yml` entry | The same check for sample data (§7) |
| Integration CI | `.github/workflows/hbr-check.yml`: RuboCop, tests, then `db:create db:migrate` from empty | Gains a step that loads the sample data (§7) |

## 3. How it's run

```bash
# From a checkout of a build (for example the integration worktree):
bin/rails hbr:sample_data

# From a tagged image, with the stack running:
docker compose exec web bin/rails hbr:sample_data
docker compose restart web worker   # so the app sees the feature flags (BL-013)
```

It prints one line per layer ("base: 7 teams, 32 people…", "feature/forms: 4 forms, 19 responses") and any warnings. Running it again is safe: it updates the same records and resets their dates (§5).

## 4. Layout

```
fork/sample_data/
  README.md               how to load it, logins, what's in it (§8)
  sample_data.rb          Hbr::SampleData: the runner, guards, helpers (§5, §6)
  base.rb                 Northwind: teams, people, logins, badges, events, periods, cards
  features/
    search-and-add.rb     one file per manifest branch, named for the branch
    forms.rb              without the feature/ prefix
    ...
lib/tasks/hbr_sample_data.rake   the hbr:sample_data task: requires fork/sample_data/sample_data.rb and runs it
```

- **Fork-only code is namespaced** (`Hbr::SampleData`, STRATEGY rule 5). It's not autoloaded; the task requires it.
- **Which features load.** The runner reads `fork/features.txt` from the working tree (it's present in every build and image), skips commented lines, and loads `features/<name>.rb` for each branch, in manifest order, after `base.rb`. A manifest branch with no file is a warning in the output, and the load continues.
- **Each feature file is a block** registered with the runner: `Hbr::SampleData.feature "feature/forms" do |s| ... end`. `s` gives the helpers and the base records (`s.person("Ben")`, `s.team(:youth)`, `s.login(:admin)`).
- **A feature with nothing to add still has a file**, containing one `s.note "..."` line saying what in the base layer exercises it. That keeps the coverage check simple and documents the decision.

## 5. Data rules

- **Find or create by a stable key**: a name, an email, or a `key` column where the model has one. Never by generated ids.
- **Relative dates.** Every date or time comes from helpers anchored to the run: `s.days_from_now(7)`, `s.next_weekday(:saturday, hour: 9)`, `s.days_ago(1, hour: 18)`, `s.season` (from the first of last month to the end of next June). Each run sets these again on records it owns, so re-running refreshes them.
- **Mixed states on purpose.** Each feature's data covers its states, not just the happy path: open and overdue, signed and unsigned, one choice and two, filled and empty.
- **Through the models.** Records are created with the normal models and validations, never raw SQL, so the data is what the app itself would produce.
- **Logins.** Every login uses `@example.com` and the password `password123`. Each persona the features need gets one, so testers can sign in as each role (§9 lists them).

## 6. Guards

The published image runs in the `production` environment, so the guard can't be the Rails environment. It checks the data:

- **Refuse** if any `User` has an email outside `@example.com`, or any `Person` exists that `db/seeds.rb` or the loader didn't create ("Test First Name …" or a sample name). The message names the first few records it found.
- `SAMPLE_DATA_FORCE=1` overrides, for a copy someone deliberately wants mixed.
- Turning on feature flags is part of the load. A feature's flag is set to on only for features in the build.

## 7. Keeping it complete

1. **Rebuild warning.** `bin/fork-changelog` adds "`<branch>` has no sample data in `fork/sample_data/features/`" to its warnings, beside the catalog warning.
2. **CI.** In `hbr-check.yml`, after "Migrate from an empty database", a step runs `bin/rails hbr:sample_data` twice against that database. The second run proves it's re-runnable. Any exception fails the job, as does any coverage warning (a missing feature file) in `ref` and `rebuild` modes. Each feature file can also declare checks (`s.expect Form.count >= 4`) that fail the run if they're false.
3. **Strategy.** `fork/STRATEGY.md` "The Feature Manifest" gains: a branch joining the manifest needs a `fork/catalog.yml` entry **and** a sample data file. A feature change that adds a state or a screen updates its file in the same work session.

## 8. Documentation

The build writes or updates these; none is an upstream file.

- **`fork/sample_data/README.md`** (new): how to load from a checkout and from a tagged image (§3), including the restart and BL-007 (below); the logins and what each is for; the team tree; scan card numbers; a short "things to try" list per feature; how to add data for a new feature. Replaces `~/dev/gatherpack-dev-data/README.md`, which then points here.
- **`HBR-CHANGELOG.md`**: `bin/fork-changelog` adds a short "Try this build" section with the load command, the admin login and a link to the README.
- **`FORK.md`**: one line under the intro linking the README.
- **`fork/STRATEGY.md`**: the manifest rule in §7.

`docs/self-hosting.md` is upstream's file and stays untouched.

**BL-007 note.** Until BL-007 is fixed, `db:prepare` on an empty database crashes in `db/seeds.rb`, so a brand-new stack from a tagged image doesn't start. The README gives the workaround that works today, verified when building this (expected: start once with `SKIP_DB_PREPARE=true`, run `bin/rails db:create db:schema:load`, then load the sample data).

## 9. What each feature's file adds

Base layer, from `populate_dev.rb`: logins `admin@example.com` (Adam Admin) and `manager@example.com` (Mara Manager, Programs); the Northwind tree; 30 members with repeating last names; badges First Aid, Forklift Operator, Youth Protection, Volunteer of the Month; the Workday event type with check-in fields; events moved to relative dates (Spring Workday 3 days out, Youth Campout next weekend, locked); time clock periods for the current season; scan cards `10000001`–`10000032`.

| Branch | Adds |
|---|---|
| `search-and-add` | Note only. Base has candidates for every panel: people not yet on a crew, a badge few people hold, an upcoming event with spare places |
| `enforce-authorization` | Note only. Exercised by signing in as the member login (below) |
| `people-ransack-auth-object` | Note only |
| `person-fields` | A guardianship relationship type ("Parent of"); two parent logins (`parent1@`, `parent2@`) linked to three Youth Program members, one of them 17 and turning 18 within a month; a member login (`member@`, Ella); fields at each read level: Medical Notes (self, guardians, leaders, plus a "Health Officer" badge grant held by Grace), Emergency Contact (self and leaders), Allergies (everyone), Photo Release (yes/no, guardians write); sections "Health" and "Contact"; values filled for some people and empty for others |
| `forms` | Season form "Meal Choices" (open, due in 14 days, linked allergies question, responses from half the audience); "Parent Consent" (guardian signature, completion badge "Consent Signed", one signed, one waiting for a guardian, one needing re-confirmation after a profile change); an event form on Youth Campout with an intent question (yes, no and unanswered); one overdue form; one closed form; a badge for student form creators held by Chloe |
| `app-version` | Note only. Set by the image build (`GATHERPACK_VERSION`) |
| `widgets` | A Markdown widget at the top for everyone ("Welcome to Northwind"); a dynamic widget on the right for managers listing their teams' open punches; a CSS-styled widget on the left |
| `signup-link-guard` | Note only. Exercised by turning off "Enable Creating Local Accounts" |
| `kiosk-scanned-person` | Note only. Uses base cards and periods |
| `kiosk-auto-clock-in` | A "Kiosk" team with one plain login (`kiosk@`); a second, Youth-only period so Youth members have two periods; Ben clocked in an hour ago; Grace with an open punch from yesterday evening; Henry clocked in and out earlier today. Leaves the three kiosk settings at their defaults; the README says which to change to try auto clock-in |

## 10. Hooks

None added. The loader creates records through the models, so any configured Hook fires as it would for a person entering the same data. On a fresh database the only Hook is upstream's seeded "Test Hook" (`announcement - update`, a string literal), and the loader creates no announcements, so nothing runs. The loader doesn't create Hooks: a sample Hook would run architect code on every tester's copy. A sample data load is not a domain event anyone would integrate with, so it gets no catalog entry.

## 11. Tests

- `test/fork/sample_data_test.rb`, run like the changelog tests (`ruby test/fork/sample_data_test.rb`, no database): manifest parsing, feature file discovery, the coverage warning, and the date helpers against a fixed clock.
- The CI step in §7 is the full test: a migrated empty database, loaded twice, with every feature file's `expect` checks.
- By hand, once: load into a copy of the dev database (existing Northwind data upgrades in place), then sign in as each login and work through the README's "things to try".

## 12. Files

All on `hbr/platform`:

- New: `fork/sample_data/**`, `lib/tasks/hbr_sample_data.rake`, `test/fork/sample_data_test.rb`.
- Changed: `bin/fork-changelog` (warning and "Try this build" section) and its test, `.github/workflows/hbr-check.yml` (the load step), `fork/STRATEGY.md`, `FORK.md`.
- Afterwards, outside the repository: `~/dev/gatherpack-dev-data/README.md` points to the new README, and `populate_dev.rb` is retired.

Changes to scripts and CI on `hbr/platform` need Corey's OK before pushing.

## 13. Open questions

1. Should a missing feature file fail the rebuild itself, or only CI and the changelog warning? The default here: warn in the rebuild, fail in CI.
2. Should the loader also refresh dates on a schedule for long-lived test copies (Ditto), or only when someone re-runs it? The default here: only when re-run.
