# Demo database

`bin/fork-make-demo-db` turns a production dump into `gatherpack_demo`: a working copy of production for documentation and demos, with every person outside a protected set replaced by a consistent fake one. Teams, roles, badges, forms, sign-up sheets, events, commitments, theme, dates and counts are kept, so pages and reports show the same shape of results as production.

## What it changes

**Protected accounts** keep their names, emails, logins and passwords: everyone on the team named by `DEMO_PROTECT_TEAM` (default `Mentors`) and each account in `DEMO_PROTECT_EMAILS`.

**Everyone else:**

| Data | Becomes |
|---|---|
| First, last and display names | Fake names, by gender where known. A real surname always maps to the same fake surname, so families stay together. Preferred names get their own fake first name. |
| Email (the login) | `first.last.NNNN@example.invalid` |
| Password | `DEMO_PASSWORD` (default `password123`) |
| OAuth links (`provider`, `uid`) | Cleared |
| Phone | Same layout, fictional `555-01NN` numbers |
| Address | Street replaced; city, state and ZIP after the first comma kept. A shared address stays shared. |
| Birthday | Shifted 30–180 days, never changing the person's age today |
| Bio | Cleared |
| Dietary restrictions | Cleared; about 15% of people get a made-up one |
| Avatars and other uploads | Generic placeholder images (protected accounts too: their files aren't copied) |

**Free text** (form answers and snapshots, form questions, sign-up notes, punch and check-in notes, pages, widgets, reports, hooks, and any other text column): real names, emails and phones become their fake counterparts.
- A name word that also belongs to a protected person is left as it is.
- A first name shared by several people takes the person the record is about, or a family member of theirs. Otherwise one is picked, and the record is flagged.
- Each flagged record is written to `$DEMO_HOME/flags.txt` as a table, column and id, without the text.
- Signatures get the signer's fake name, a `192.0.2.x` address and a generic browser. Signatures that were valid still verify.

**For every account:**
- Sessions are rotated.
- Reset tokens, remember-me and lockouts are cleared.
- Kiosk scan tokens get new values.

**Outside connections:**
- There are no gateways at all, as on Ditto. Every gateway (email, payments) is deleted, along with OAuth tokens, queued jobs, the cache and inbound mail. GatherPack sends all mail through gateways, Devise's password resets included, so every send is only logged ("No email gateway configured").
- Hooks that call an outside service (Slack and similar) are disabled.

**Audit history:** the versions database is created empty, because PaperTrail keeps every past value.

**Personas:** Demo Member, Demo Lead, Demo Mentor, Sam Student, Demo Veteran and Demo Parent, all with the demo password:
- `demo.member@example.invalid`: student, Class of 2029, a rookie. Two Outreach check-ins this season.
- `demo.lead@example.invalid`: Class of 2027, and manager of Student Leadership.
- `demo.mentor@example.invalid`: manager of Mentors and of Student Leadership. Organizes Concessions Stocking.
- `demo.student@example.invalid`: Class of 2028, behind. Punched in at some meetings (not enough), no Outreach, no Concessions, and the meal choices form a checklist lists is not submitted.
- `demo.veteran@example.invalid`: Class of 2027, all done. Every checklist item met (punched in at every past meeting, Outreach and Concessions check-ins) and two upcoming sign-ups.
- `demo.parent@example.invalid`: guardian of Demo Member and Sam Student, through the relationship type Concessions pools on, so the two owe Concessions together.

Each persona also has badges, form responses and up to two upcoming sign-ups, all made through the models (punches are added by an admin, as the time clock periods require). The Student and the Parent have no forms or sign-ups. One more record is added: the sign-up sheet "Outreach Booth Helpers", whose position needs the Outreach checklist. Sam Student is covered by it and hasn't finished it, Demo Member isn't covered, and nothing on the sheet counts toward Outreach. Checklist results are refreshed at the end, as the worker would.

## Orders data

`orders.rb` fills a demo with believable robotics purchasing so Orders can be seen and documented: eight suppliers (WCP, REV, AndyMark, McMaster-Carr, Amazon, Bambu Lab, CTR Electronics, The Thrifty Bot), three funding sources (Build season, Outreach, and a restricted parts grant), and about 25 requests over the last ten weeks, one for every state (draft, waiting for approval, changes asked, declined, approved, partly bought, ordered, backordered, partly received, received, closed, a price rise needing approval again, and a delivery with a problem). When the Inventory flag is on it adds a Shop with a Hardware cabinet, Electronics shelf and Motor bin, 15 counted items (a few below their reorder point), Kraken and NEO Vortex motors as tracked units, and a Practice bot machine; with order-inventory on, received lines are put on the shelf.

Run it in the demo's app checkout, after `personas.rb`, with the Orders flag on (and Inventory for the stock):

```
cd ../demo-<tag>
DATABASE_URL=postgres://postgres:password@localhost/gatherpack_demo \
VERSIONS_DATABASE_URL=postgres://postgres:password@localhost/gatherpack_demo_versions \
bin/rails runner /path/to/fork/demo_db/orders.rb
```

Then restart the app: settings are read once per process. It prints a short summary (requests and lines by state, purchases, vendors, items). Running it again creates nothing new.

- It uses the same guard as the other scripts. Everything goes through the model methods the screens use, at backdated times, so timelines look real.
- **People, by role:** requesters are students on the teams below the top team (the Demo Member, Sam Student and Demo Lead personas first); approvers and buyers come from the Mentors team, managers first. Orders decides who may approve or buy for a team, so when a mentor doesn't reach a student's team the script falls back to other team managers, then an admin. The summary counts those. To have mentors do it all, give them a mentor badge held at the top team (the script uses an admin-assigned badge with "mentor" in its name).
- **Settings,** only where blank: approval step "Mentor approval" (plus "From $500, also a lead mentor" when such a badge exists), buyers, and paid-with "Team card" and "Paid personally (reimburse)".
- **On a Northwind sample copy** (to check the script without a demo): load the sample data into a throwaway database, then name it in `ORDERS_SAMPLE_DB`:

  ```
  ORDERS_SAMPLE_DB=gp_sample_check bin/rails runner /path/to/fork/demo_db/orders.rb
  ```

  There is no Mentors team there, so team managers and the admin approve and buy. It refuses unless the database is local, isn't production and has the Northwind teams. Run it from a scratch checkout: it writes that checkout's `storage/settings.pstore`.

## Safety

The script refuses to run when:
- `RAILS_ENV` is production.
- The target name doesn't end in `_demo`.
- The database host isn't local.
- The production containers run on this machine.
- The server holds a `gatherpack_production` database.
- A database it would drop wasn't created by it. It marks its own with a `gatherpack-demo` comment.

The Ruby steps check the connected databases again before writing.

The fake names come from a keyed hash with a secret seed. It is created once in `$DEMO_HOME/seed` (mode 600), or passed in as `DEMO_SEED`. The same seed gives the same fake people on every rebuild. **Keep the seed private:** with it, a fake name could be traced back to the real one.

## Running it

1. **Take a read-only dump** of the production database, in custom format, excluding the data of secret, queue and cache tables:

   ```
   PGOPTIONS='-c default_transaction_read_only=on' pg_dump -Fc --no-owner --no-acl \
     --exclude-table-data=gateways --exclude-table-data='oauth_access_*' --exclude-table-data='solid_queue_*' \
     --exclude-table-data=solid_cache_entries --exclude-table-data=action_mailbox_inbound_emails gatherpack_production > prod.dump
   ```

   Keep it outside any git repository (mode 600), and delete it when the build has passed.

   Optionally also export:
   - **Settings** as JSON (`--settings`), without OAuth or mail credentials. The script drops secret-looking keys anyway.
   - **The theme's logo and icon files** as a tar of their storage keys (`--files`).
2. **Check out the release the dump came from.** The schema versions must match:
   ```
   git worktree add --detach ../demo-<tag> <tag>
   ```
   Its `storage/` folder receives the demo's files and settings.
3. **Optionally start Mailpit**, so verification can also show that nothing arrives there:
   ```
   docker run -d --name gatherpack-demo-mailpit -p 127.0.0.1:1025:1025 -p 127.0.0.1:8025:8025 axllent/mailpit:v1.27
   ```
4. **Build:**

   ```
   DEMO_PROTECT_EMAILS=admin@example.org bin/fork-make-demo-db --dump prod.dump --app ../demo-<tag> \
     [--settings settings.json] [--files theme-files.tar]
   ```

   The script uses the `gp-test-pg` container's `psql` by default. Set `PG_CONTAINER=` to use local client tools instead, with `DATABASE_HOST`, `DATABASE_USERNAME` and `DATABASE_PASSWORD`.
5. **Verification runs automatically.** It restores the dump a second time into `gatherpack_demo_source`, then checks:
   - No real email, phone, full name or non-protected name word is left in any column.
   - Every non-protected email ends in `@example.invalid`.
   - Passwords, tokens and sessions are reset.
   - There are no gateways, and a password reset is only logged (nothing reaches Mailpit).
   - Row counts match production apart from the personas and the cleared data.
   - Every Page and Report renders for the personas and the protected accounts.

   The second copy is then dropped. If a check fails, the script exits non-zero.
6. **Run the demo:**

   ```
   cd ../demo-<tag>
   DATABASE_URL=postgres://postgres:password@localhost/gatherpack_demo \
   VERSIONS_DATABASE_URL=postgres://postgres:password@localhost/gatherpack_demo_versions bin/dev
   ```

   Mail isn't delivered anywhere: each send is logged instead.

   In development, the "developer" sign-in option lets anyone sign in as any email without a password. Keep the demo on your own machine.
