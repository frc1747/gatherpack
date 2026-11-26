# BL-089: Static files skip the security headers Rails pages send

| | |
|---|---|
| Kind | upstream bug (hardening) |
| Priority | low (nosniff covered for HBR) |
| Status | not started (HBR's nosniff covered by a Cloudflare rule since 2026-11-25) |
| Added | 2026-11-25 (widened 2026-11-26) |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | `feature/static-headers` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

Rails pages get their security headers from `action_dispatch.default_headers` and the CSP initializer. Files served from `public/` (`/assets/*.js`, `*.css`, `robots.txt`, `offline.html`, the error pages) go through the public file server, which sends only `public_file_server.headers`, so they carry none of them. Every ZAP scan of Ditto flags the gap:

| Header | Missing on | ZAP alert |
|---|---|---|
| `X-Content-Type-Options: nosniff` | every static file | Low (Cloudflare adds it for HBR) |
| `Permissions-Policy` | every static file | Low |
| `X-Frame-Options` / CSP `frame-ancestors` | `offline.html` and the error pages: the only HTML that can be framed | Medium, "Missing Anti-clickjacking Header" |
| `Cross-Origin-Resource-Policy` | every static file | Low |

Pages also send no `Cross-Origin-Opener-Policy` (ZAP Low on `/`).

The risk is small. `offline.html` and the error pages hold no actions, so framing them achieves nothing. Modern browsers rarely sniff types, and static files have no use for camera access. Each fix is a line of config.

## Where things are (upstream `3d5ce8f96`)

- `config/environments/production.rb:27`: `public_file_server` left at its defaults; no `headers` set.
- `config/environments/development.rb:27` and `test.rb:21` set only `Cache-Control`.
- Fork (on `hbr/integration` `4d53cddfc`): `config/initializers/permissions_policy.rb` sets `Permissions-Policy` in `default_headers`, which reaches pages only.

## Proposed fix

1. `config/environments/production.rb`: `config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.year.to_i}, immutable", "X-Content-Type-Options" => "nosniff", "X-Frame-Options" => "SAMEORIGIN", "Cross-Origin-Resource-Policy" => "same-origin" }`. Keep the cache header the image sends today (`public, max-age=31556952, immutable`).
2. Fork, in the same initializer that sets `Permissions-Policy`: also merge it into `public_file_server.headers`, so static files get the same policy.
3. `default_headers["Cross-Origin-Opener-Policy"] = "same-origin"`. Check that Stripe Checkout and the Google and Microsoft sign-ins still return to the app: they're full-page redirects, not popups, so this shouldn't affect them.
4. Not `Cross-Origin-Embedder-Policy: require-corp`: it would block the Google Fonts stylesheet and buys nothing without features that need cross-origin isolation.

## Tests

- Request spec (production-like config): `GET /assets/<digest>.js` and `GET /offline.html` return `nosniff`, `X-Frame-Options: SAMEORIGIN`, `Cross-Origin-Resource-Policy: same-origin` and the existing `Cache-Control`.
- Request spec: a page response carries `Cross-Origin-Opener-Policy: same-origin`.
- Smoke on Ditto: Stripe Checkout, Google sign-in and Microsoft sign-in each come back signed in.

## Fork strategy notes

Upstream file edit (`production.rb`): add it to `FORK.md` "Upstream files touched". Step 2 is fork-only. Confirm with Corey before any issue or PR. A Cloudflare response-header rule could cover HBR without code, but other GatherPack installs need the code fix.
