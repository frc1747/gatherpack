# BL-088: Turn the Content-Security-Policy from report-only to enforced

| | |
|---|---|
| Kind | fork-only (follows `feature/security-series`) |
| Priority | medium |
| Status | not started |
| Added | 2026-11-25 |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | on `feature/security-series` |
| Upstream issue / PR | none |

## Summary

`feature/security-series` (`e48be7c0e`) sends a Content-Security-Policy with a per-response script nonce, but in report-only mode: browsers log violations and block nothing. Both ZAP scans of Ditto (unauthenticated and authenticated) report it as "CSP Header Not Set" (Medium) plus "CSP Report-Only Header Found". Until it's enforced it gives no protection against injected scripts.

## Where things are

- `config/initializers/content_security_policy.rb` (on `hbr/integration` at `4d53cddfc`): `config.content_security_policy_report_only = true`. `style-src` allows `'unsafe-inline'` and fonts.googleapis.com; `script-src` is `'self'` plus the nonce.

## Proposed fix

1. Collect violations: open the main screens on Ditto in Chrome as an admin, a manager, a member and a guardian (Home, People, a profile, Events and check-in, Forms fill and edit, Orders, Inventory, Checklists, Pages with widgets, Setup, kiosk, intake), and record every console CSP report.
2. Fix each one (missing nonce on a script tag, inline `onclick`, a third-party host).
3. A site setting "Enforce content security policy" (default off, rule 10). On: the header is `Content-Security-Policy`; off: report-only as now. Turn it on in Ditto, then production.

## Tests

- Request spec: with the setting on, responses carry `Content-Security-Policy` (not `-Report-Only`) with a nonce; off, the report-only header as today.
- System spec smoke over the screens above with the setting on: no console CSP errors.

## Fork strategy notes

The CSP itself is part of the security series (upstream's `sec/10-hand-punches`), so the switch lives there too. Self-hosting the Google fonts (also flagged by ZAP as missing SRI, which Google Fonts can't support) would let `style-src`/`font-src` drop the Google hosts; optional, not part of this item.
