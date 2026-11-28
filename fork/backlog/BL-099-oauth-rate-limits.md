# BL-099: OAuth endpoints have no rate limit

| | |
|---|---|
| Kind | upstream gap + fork (MCP) |
| Priority | medium |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | `feature/security-series` |
| Upstream issue / PR | none yet |

## Summary

`/oauth/token`, `/oauth/authorize`, `/oauth/revoke` and `/oauth/introspect` have no request limit, and `/mcp` counts requests only after a token is accepted, so guessing client secrets or tokens isn't slowed down. The rest of the OAuth setup reads as sound (no open client registration, exact redirect matching, PKCE S256 required, consent always shown); the checks in Tests confirm it on Ditto.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `config/initializers/doorkeeper.rb`: `force_pkce`, S256 only; `skip_authorization` off.
- `app/controllers/mcp_controller.rb:12`: 120 a minute per token id, after authentication.
- `app/controllers/mcp/authorization_checks.rb`: a comment says `force_pkce` isn't set; it is (stale).

## Proposed fix

Rails `rate_limit` (or the existing Rack::Attack rules, if the fork has them) on the OAuth endpoints per IP (e.g. 20 a minute for `/oauth/token`), and per IP on failed `/mcp` authentication. Fix the stale comment.

## Tests

- 30 bad `client_secret` posts to `/oauth/token` from one IP: a 429 before the end.
- Ditto checks of the rest: `redirect_uri` with `/../`, another port or a trailing slash is refused; `/oauth/authorize` without `code_challenge` or with `plain` is refused; `POST /oauth/authorize` without a CSRF token gives 422; introspecting another application's token gives `active: false`.

## Fork strategy notes

Doorkeeper config is upstream; MCP is fork. Confirm with Corey before any upstream issue.
