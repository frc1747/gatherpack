# Self-Hosting GatherPack

GatherPack ships as a single container image that runs the Rails app, plus a
PostgreSQL database. Caching, background jobs, and websockets all live in
PostgreSQL via SolidCache, SolidQueue, and SolidCable.

[`docker-compose.production.yml`](../docker-compose.production.yml) runs three
containers:

| Service  | What it does                                                              |
| -------- | ------------------------------------------------------------------------- |
| `web`    | Puma. Applies migrations on boot, then serves the app on port 3000.        |
| `worker` | `bin/jobs` — SolidQueue background jobs and the `config/recurring.yml` schedule. |
| `db`     | PostgreSQL 16 with a persistent named volume.                             |

Two named volumes hold everything that must survive a redeploy:

- `db_data` — the PostgreSQL data directory.
- `storage` — Active Storage uploads **and** `storage/settings.pstore`, which is
  where runtime settings (Postmark key, OAuth credentials, feature flags) are
  kept. Losing this means reconfiguring the instance from scratch.

## Images

Images are published to the GitHub Container Registry by
[`.github/workflows/build.yml`](../.github/workflows/build.yml) for `linux/amd64`
and `linux/arm64`. Publishing is gated on the security scans, the linter, and a
clean image build passing on that commit. It is **not** gated on the test suite,
which currently fails for pre-existing reasons — see the note in
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml). Treat a published
image as "builds and passes static analysis", not "passes tests".

```
ghcr.io/gatherpack/gatherpack:latest    # newest tagged release
ghcr.io/gatherpack/gatherpack:edge      # newest commit on main
ghcr.io/gatherpack/gatherpack:1.2.3     # a specific release
ghcr.io/gatherpack/gatherpack:sha-abc123
```

Production instances should pin `GATHERPACK_TAG` to a release rather than
tracking `latest`. If you run a fork, set `GATHERPACK_IMAGE` to your own
registry path — the workflow always publishes to the repository it runs in.

## Quick start with Docker Compose

```bash
git clone https://github.com/GatherPack/gatherpack.git
cd gatherpack
cp .env.production.example .env
```

Fill in the four required values in `.env` (`SECRET_KEY_BASE`, `ROOT_URL`,
`DATABASE_PASSWORD`, `JOBS_DASHBOARD_PASSWORD`), generating the secret with:

```bash
openssl rand -hex 64
```

Then:

```bash
docker compose -f docker-compose.production.yml up -d
```

The `web` container creates and migrates the databases on first boot, so it
takes a minute or two before it reports healthy. Watch it with:

```bash
docker compose -f docker-compose.production.yml logs -f web
```

## Reverse proxies and TLS

The `web` container publishes port 3000 on the host (`GATHERPACK_PORT`). Point
your reverse proxy at it, terminate TLS there, and then set **both**:

```
FORCE_SSL=true    # redirect http -> https, mark cookies secure, send HSTS
ASSUME_SSL=true   # trust that the proxy already terminated TLS
```

Setting `FORCE_SSL` without `ASSUME_SSL` produces a redirect loop. Setting
either one while the app is genuinely served over plain HTTP breaks sign-in,
because the session cookie is marked secure and never comes back. Both default
to `false` so a first boot over `http://host:3000` works; turn them on once TLS
is in front.

The health check endpoint `/up` is excluded from both the HTTPS redirect and
`Host` header validation, so container and load balancer probes work without
any extra configuration.

Limit request body sizes at the proxy as well (nginx `client_max_body_size`,
Caddy `request_body { max_size }`). Set it to the largest upload you accept;
GatherPack refuses gateway webhook bodies over 1 MB itself.

`ROOT_URL` must be the full public URL including the scheme
(`https://gather.example.com`). It drives the hostname allowed by Rails' DNS
rebinding protection and the URLs generated in outgoing email.

## First run

1. Visit `ROOT_URL` and create an account. **The first user to sign up is
   automatically made an admin.** Do this immediately after deploying.
2. Go to `/settings` to configure mail (Postmark API key), OAuth providers,
   and feature flags. These are stored on the `storage` volume, not in
   environment variables.
3. `/setup` links to the rest of the initial configuration, and `/jobs` shows
   the background job dashboard (protected by the HTTP basic auth credentials
   in `JOBS_DASHBOARD_USER` / `JOBS_DASHBOARD_PASSWORD`).

## Payment and email gateways

Gateways (Stripe, Postmark, Resend, SMTP) are set up by an architect at
`/gateways`. Their webhook URLs are public, so GatherPack checks every webhook
request before acting on it:

- Stripe events must carry a valid `Stripe-Signature`. A Stripe gateway without
  a webhook signing secret refuses every event, and its page says it isn't
  ready. Copy the endpoint's signing secret from the Stripe dashboard into the
  gateway's Secret field.
- Resend events must carry a valid Svix signature. A Resend gateway without a
  webhook signing secret refuses them the same way.
- Postmark inbound mail must sign in with the user name and password in the
  receiving gateway's webhook URL, shown on its page. Paste that whole URL into
  the Postmark server's inbound webhook setting, and again whenever you
  regenerate the password; until then inbound mail is refused with 401.
- Requests to any other gateway's webhook URL are refused with 400. That
  includes the bounce and spam-complaint webhook a Postmark sending gateway
  registers with Postmark; GatherPack never acted on those events, so delete
  that webhook in Postmark or ignore its failed deliveries.
- Webhook bodies over 1 MB are refused with 413, and more than 120 webhook
  requests a minute from one address get 429.

## Stored secrets and encryption keys

Gateway API keys, tokens and passwords are encrypted in the database with
Active Record encryption. Each of its three keys is taken, in order, from:

1. `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
   `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and
   `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` (generate values with
   `bin/rails db:encryption:init`);
2. the `active_record_encryption` section of the Rails credentials;
3. otherwise, a key derived from `SECRET_KEY_BASE`.

Setting explicit keys later is safe as long as `SECRET_KEY_BASE` stays the
same: secrets saved with the derived keys stay readable, but they still depend
on `SECRET_KEY_BASE` until they are encrypted again with the new keys. To move
them, set the explicit keys, restart, and run
`docker compose -f docker-compose.production.yml exec web ./bin/rails gateways:reencrypt`
before you change `SECRET_KEY_BASE`.

Changing `SECRET_KEY_BASE` while relying on derived keys, or replacing explicit
keys, makes the stored secrets unreadable. Gateway pages then say so: enter the
secrets again on each gateway's edit page, or restore the old keys (the
unreadable secrets stay stored until they are entered again or cleared from
the gateway page).

### Upgrading from plain-text gateway secrets

- The migrations move existing secrets into the encrypted column. Rolling them
  back moves them back into the plain `configuration` column.
- Audit log rows written before the upgrade still contain the old secrets.
  Remove them with
  `docker compose -f docker-compose.production.yml exec web ./bin/rails gateways:scrub_audit_log`,
  then **rotate every gateway key** (Stripe, Postmark, Resend, SMTP): backups
  taken before the upgrade still contain them.

## Using an external PostgreSQL server

Set `DATABASE_HOST`, `DATABASE_USERNAME`, and `DATABASE_PASSWORD` to point at
your server and delete the `db` service (along with the `depends_on` entries
referencing it) from the compose file.

GatherPack uses **three** databases on that server, all created automatically
on boot, so the user needs `CREATEDB`:

- `gatherpack_production` — the application, plus SolidQueue and SolidCache
- `gatherpack_production_versions` — the PaperTrail audit log
- `gatherpack_production_cable` — SolidCable websocket messages

## Backups

Back up the PostgreSQL databases and the `storage` volume together.

```bash
# Databases
docker compose -f docker-compose.production.yml exec db \
  pg_dumpall -U gatherpack > gatherpack-$(date +%F).sql

# Uploads and settings
docker run --rm -v gatherpack_storage:/storage -v "$PWD:/backup" alpine \
  tar czf /backup/gatherpack-storage-$(date +%F).tar.gz -C /storage .
```

`pg_dumpall` is used rather than `pg_dump` because of the three databases
above.

Keep `SECRET_KEY_BASE` (and the `ACTIVE_RECORD_ENCRYPTION_*` keys, if you set
them) safe alongside the backups. Gateway secrets in a restored database can
only be read with the same keys.

## Operating the stack

```bash
# Rails console
docker compose -f docker-compose.production.yml exec web ./bin/rails console

# Follow logs
docker compose -f docker-compose.production.yml logs -f web worker

# Run migrations by hand (normally automatic on web boot)
docker compose -f docker-compose.production.yml exec web ./bin/rails db:prepare
```

## Tuning

`WEB_CONCURRENCY` sets Puma worker processes (start at the number of CPU
cores) and `RAILS_MAX_THREADS` sets threads per process, which also sizes the
database connection pool. Total connections to PostgreSQL are roughly
`WEB_CONCURRENCY × RAILS_MAX_THREADS` for the web container plus the worker's
own pool, so raise `max_connections` on an external database accordingly.

To run jobs inside the web process instead of a separate container — a smaller
single-container deploy — remove the `worker` service and set
`SOLID_QUEUE_IN_PUMA=true` on `web`.
