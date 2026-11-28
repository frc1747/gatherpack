# BL-098: Locked accounts and "sign out everywhere" keep working MCP tokens

| | |
|---|---|
| Kind | fork bug (security, `feature/mcp`) |
| Priority | high |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | fix on `feature/mcp` |
| Upstream issue / PR | none yet |

## Summary

An MCP request is accepted with any valid access token. Locking an account (Devise lockable) only stops password sign-in, and rotating the session ("sign out everywhere") doesn't revoke OAuth tokens, so a locked or signed-out member's connected assistant keeps working until its tokens expire (access 2 hours, refresh up to 30 days).

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/controllers/mcp_controller.rb:46-62`: token authentication; no `access_locked?` / `active_for_authentication?` check.
- `app/models/user.rb:15-20,56,140`: `revoke_api_access` runs on password change and kiosk/admin changes, not on lock or session rotation.

## Proposed fix

`McpController`: refuse (401) when the token's user is locked or not `active_for_authentication?`. Call `revoke_api_access` when an account is locked and when the session token rotates.

## Tests

- Request spec: lock the user; `/mcp` with their token gives 401; unlock: works again only with a new token.
- "Sign out everywhere": the old access and refresh tokens no longer work.

## Fork strategy notes

Fork-only (`feature/mcp`).
