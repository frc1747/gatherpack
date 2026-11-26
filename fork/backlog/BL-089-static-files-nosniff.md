# BL-089: Static files under /assets lack X-Content-Type-Options: nosniff

| | |
|---|---|
| Kind | upstream bug (hardening) |
| Priority | low (covered for HBR) |
| Status | not started (HBR covered by a Cloudflare rule since 2026-11-25) |
| Added | 2026-11-25 |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | `feature/static-nosniff` (from `upstream/main`), or a Cloudflare rule instead |
| Upstream issue / PR | none yet |

## Summary

Rails pages send `X-Content-Type-Options: nosniff` (Rails' default headers), but files served from `public/` (`/assets/*.js`, `*.css`, `robots.txt`) don't, because the public file server only sends `public_file_server.headers`. ZAP flags it (Low) on every scan of Ditto. Modern browsers rarely sniff, so the risk is small; the fix is one line.

## Where things are (upstream `3d5ce8f96`)

- `config/environments/production.rb:27`: `public_file_server` left at defaults; no `headers` set.
- `config/environments/development.rb:27` and `test.rb:21` set only `Cache-Control`.

## Proposed fix

`config/environments/production.rb`: `config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.year.to_i}, immutable", "X-Content-Type-Options" => "nosniff" }` (keep the cache header the image sends today: `public, max-age=31556952, immutable`).

Alternative with no code: a Cloudflare response-header Transform Rule on hbrlive.com adding `X-Content-Type-Options: nosniff` for `/assets/*`. Cheaper, but only covers HBR, not other GatherPack installs. HBR turned on the Cloudflare rule (2026-11-25): team., ditto. and demo.hbrlive.com now send `nosniff` on every response, once. The code fix is still worth doing for other GatherPack installs; it can wait for a convenient upstream PR.

## Tests

- Request spec (production-like config): `GET /assets/<digest>.js` returns `X-Content-Type-Options: nosniff` and the existing `Cache-Control`.

## Fork strategy notes

Upstream file edit (`production.rb`): add to `FORK.md` "Upstream files touched". Confirm with Corey before any issue or PR.
