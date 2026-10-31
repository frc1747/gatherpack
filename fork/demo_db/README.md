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

**Personas:** Demo Member, Demo Lead and Demo Mentor, all with the demo password:
- `demo.member@example.invalid`: student, Class of 2029.
- `demo.lead@example.invalid`: Class of 2027, and manager of Student Leadership.
- `demo.mentor@example.invalid`: manager of Mentors and of Student Leadership. Organizes Concessions Stocking.

Each persona also has badges, two form responses and up to two upcoming sign-ups, all made through the models.

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
