# Sample data

Every HBR build can load the same sample organization, the **Northwind Community**, with data for each feature in that build: forms with deadlines still ahead, custom fields at different privacy levels, parents and their children, dashboard widgets, and time kiosk cards. Every date is set relative to when you load it, so a release loaded months from now still has upcoming events and open forms.

Use it on a test copy only. It refuses to load into a database that has real people in it (see [Safety](#safety)). To just look around, [try it in a container](#try-it-in-a-container).

## Try it in a container

The quickest way to see what HBR has built: run a release in Docker with the sample data loaded. You need Git, Docker with Compose v2, and `openssl`. It runs as its own stack, so it can't touch any other GatherPack you run.

**1. Get the release.** The image comes from GitHub's registry; the repository supplies the compose file. Pick a release from the [tags](https://github.com/frc1747/gatherpack/tags):

```bash
git clone https://github.com/frc1747/gatherpack.git hbr-gatherpack-demo
cd hbr-gatherpack-demo
git checkout v0.0.0-hbr.13
```

**2. Write its settings.** This makes random secrets, serves it at `http://localhost:3000`, and names the stack `hbr-demo` so its containers and data stay separate. Set `GATHERPACK_TAG` to the tag you checked out, without the leading `v`:

```bash
cat > .env <<SETTINGS
COMPOSE_PROJECT_NAME=hbr-demo
GATHERPACK_IMAGE=ghcr.io/frc1747/gatherpack
GATHERPACK_TAG=0.0.0-hbr.13
ROOT_URL=http://localhost:3000
SECRET_KEY_BASE=$(openssl rand -hex 64)
DATABASE_PASSWORD=$(openssl rand -hex 16)
JOBS_DASHBOARD_PASSWORD=$(openssl rand -hex 16)
SETTINGS
```

If something else already uses port 3000, add `GATHERPACK_PORT=3001` and change `ROOT_URL` to match.

**3. Start it with the sample data.** The first command downloads the images, which takes a few minutes the first time:

```bash
docker compose -f docker-compose.production.yml up -d db
docker compose -f docker-compose.production.yml run --rm web ./bin/rails db:create db:schema:load
docker compose -f docker-compose.production.yml run --rm web ./bin/rails hbr:sample_data
docker compose -f docker-compose.production.yml up -d
```

Why not just `up -d`? On an empty database the web container runs `db/seeds.rb`, which currently crashes (BL-007). Loading the schema first skips it, and after that `up -d` only migrates.

**4. Open it.** Go to `http://localhost:3000` (allow a minute on the first start) and sign in as `admin@example.com` with the password `password123`. [Logins](#logins) lists the other people to sign in as, and [Things to try](#things-to-try) walks through each feature.

**Stop it, or remove it:**

```bash
docker compose -f docker-compose.production.yml stop      # start it again with: up -d
docker compose -f docker-compose.production.yml down -v   # remove its containers and all of its data
```

To try a newer release, remove the old one with `down -v`, check out the new tag, change `GATHERPACK_TAG` in `.env`, and repeat step 3.

## Load it into an existing copy

### From a checkout

From any checkout of a build (for example the `integration` worktree), with the database migrated:

```bash
bin/rails hbr:sample_data
```

Restart the app afterwards (or start it now). It turns features on in Settings, and a running app only sees setting changes after a restart.

Settings live in that checkout's `storage/settings.pstore`, and some tests read that file rather than a temporary copy. After loading sample data into a checkout, tests that expect a feature to be off fail there. Copy `storage/settings.pstore` aside before loading and put it back before running tests, or load into a different checkout.

### Into a running stack

```bash
docker compose -f docker-compose.production.yml exec web ./bin/rails hbr:sample_data
docker compose -f docker-compose.production.yml restart web worker
```

### Running it again

Safe at any time. It finds the same records and sets their dates again, so events, deadlines and punches move back to "upcoming" and "today". Responses and signatures that already exist are left alone. Nothing reloads on a schedule; re-run it when a copy gets stale.

## Logins

Every login uses the password `password123`.

| Email | Person | What they show |
|---|---|---|
| `admin@example.com` | Adam Admin | Admin; manages Northwind Community |
| `manager@example.com` | Mara Manager | Manages Programs (Youth Program and Adult Education) only |
| `member@example.com` | Ella Brown | An ordinary member of Facilities Crew |
| `parent1@example.com` | Paula Miller | Guardian of Grace Miller (16) and Kate Moore (14) |
| `parent2@example.com` | Owen Walker | Guardian of Olive Walker, who turns 18 within a month |
| `kiosk@example.com` | Kiosk Account | The only member of the Kiosk team, for the kiosk screen |

Crew leads (no login): Ava (Facilities), Ben (Logistics), Chloe (Youth Program), Dan (Adult Education).

```
Northwind Community (Organization)
├── Operations (Division)
│   ├── Facilities Crew   (lead: Ava)
│   └── Logistics Crew    (lead: Ben)
└── Programs (Division)   (manager: Mara Manager)
    ├── Youth Program     (lead: Chloe)
    └── Adult Education   (lead: Dan)
Kiosk (Organization)      (Kiosk Account)
```

30 members, with repeating last names (Smith, Smithers, Smithson and so on) so a search for "smi" finds several.

## Scan cards

Cards `10000001` to `10000032`, one per Northwind person in last-name order. Type the number into the kiosk's card box, or print barcodes for them. A few to start with:

| Card | Person | At the kiosk |
|---|---|---|
| `10000023` | Ben Smithers | Already clocked in |
| `10000017` | Grace Miller | Still clocked in from yesterday evening (missed clock-out); Youth Program, so two periods |
| `10000006` | Henry Davis | Clocked in and out earlier today |
| `10000002` | Ella Brown | Not clocked in; one period |
| `10000020` | Kate Moore | Not clocked in; Youth Program, so two periods |
| `10000016` | Mara Manager | A manager: the kiosk shows the Manager button |

## Things to try

**Search and add.** As the admin, open a team's members, a badge's holders (First Aid has three) or Spring Workday's check-ins, and add people from the search panel beside the list.

**Permission checks.** Sign in as `member@` and try to change Ava's check-in on Spring Workday, or delete Facilities Crew: both are refused. As `manager@`, only Programs teams can be managed.

**Person fields** (Setup → Person Fields). Medical Notes is seen by the person, their guardians and their leaders, plus anyone with the Health Officer badge (Isla Lopez). Emergency Contact: the person and their leaders. Allergies: everyone. Photo Release: family, and only guardians can change it. Sign in as `parent1@` to see and edit Grace's and Kate's fields; as `member@` to see what a teammate can't see; or use **Preview as…** on a profile. Olive's guardianship ends when she turns 18 (Settings: Guardianship Age Limit is 18).

**Forms.**
- *Meal Choices*: open for everyone, due in two weeks, about half answered. Totals are shared with everyone asked. Its Allergies question updates the profile.
- *Parent Consent* (Youth Program): Grace's is complete and signed by Paula, which awarded her the Consent Signed badge. Kate's waits for a guardian's signature. Olive's needs re-confirmation, because her medical notes changed after Owen signed. Sign in as `parent1@` to sign Kate's.
- *Youth Campout: Are You Coming?*: attached to the campout, with Yes, Maybe and No answers. Open the event to see expected against checked in.
- *Volunteer T-Shirt Order*: closed two days ago with answers still missing; leaders can enter late answers.
- Chloe holds the Form Creator badge, so she could create event polls for Youth Program.

**Widgets** (dashboard). A welcome note for everyone at the top; "Clocked In Now: Programs" for Programs managers (sign in as `manager@`); a styled checklist for Youth Program members.

**Sign-up link.** In Settings, turn off Enable Creating Local Accounts, sign out, and open Forgot Password: there's no sign-up link and no error.

**Time kiosk.** Open the Time Kiosk and type the card numbers above. To try auto clock-in, in Settings → Time Clock turn off **Kiosk: Allow Unassigned Punches**, then scan Ella (one period: clocked in immediately) and Kate (two periods: she chooses). Set **Kiosk: Return to Welcome After** to 10 to see the screen clear itself, and **Kiosk: Who Can Open the Kiosk** to Kiosk to limit it to `kiosk@` (and admins).

## Safety

- It refuses to run if any login is outside `@example.com`, or any person exists that neither this data nor `db/seeds.rb` creates. The message names what it found. `SAMPLE_DATA_FORCE=1` loads it anyway; don't do that on a real site.
- It turns on the Custom Person Fields, Forms and Widgets features, and sets Guardianship Age Limit and Form Creator Badge.
- Nothing it creates is a Hook, so loading it runs no admin-written code beyond any Hooks already on the site.

## Adding data for a feature

Each branch in `fork/features.txt` has a file in `features/`, named for the branch without `feature/` (`feature/forms` → `features/forms.rb`). The rebuild warns when one is missing, and CI fails.

```ruby
Hbr::SampleData.people "Pat Example"   # every person the file creates, for the safety check

Hbr::SampleData.feature "feature/example" do |s|
  s.enable_feature :example                                   # the feature's flag, if it has one
  pat = s.person!("Pat", "Example")                           # find or create, by name
  s.member!(pat, s.team(:youth))                              # base teams: :root, :operations, :programs, :facilities, :logistics, :youth, :adult
  s.upsert!(Event, { name: "Example Night" },                 # find by the first hash; set the second on every run
    team: s.team(:youth), start_time: s.clock.days_from_now(5, hour: 18), end_time: s.clock.days_from_now(5, hour: 20))
  s.report "1 event"                                          # one line in the output
  s.expect("Pat is on Youth Program") { pat.teams.include?(s.team(:youth)) }
end
```

- Dates come from `s.clock`: `days_from_now`, `days_ago`, `hours_ago`, `next_weekday(:saturday, hour: 16)`, `date(n)` and `season`.
- Base records: `s.person("Ben")` (base first names are unique), `s.team(:youth)`, `s.login(:admin)` (also `:manager`, and `:member`, `:parent1`, `:parent2`, `:kiosk` from feature layers), and `s.recall(:season)` for the season period.
- Cover the feature's states, not just the happy path, and go through the same model methods the app uses so the data is what real use produces.
- A feature with nothing to add still gets a file with one `s.note "..."` saying what in the base data exercises it.
- `ruby test/fork/sample_data_test.rb` checks the manifest and the date helpers; CI loads everything twice into an empty database.

See `fork/specs/sample-data-spec.md` for the design.
