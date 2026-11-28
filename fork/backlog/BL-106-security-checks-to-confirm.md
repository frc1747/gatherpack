# BL-106: Security checks to confirm on Ditto (expected fine)

| | |
|---|---|
| Kind | security (checks) |
| Priority | low |
| Status | not started (checks, not known bugs) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | none (results go in the skill's run book) |
| Upstream issue / PR | none yet |

## Summary

Code reading found these sound, but each is worth one confirming check on Ditto, then a row in the `security-scan` run book so it's repeated.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- Markdown fields (bio, team description, announcements, replies, application messages, sheet, checklist and form text) use Redcarpet `filter_html` + `sanitize` (`app/helpers/application_helper.rb:121-123`).
- Hooks (`app/models/hook.rb:48`) and Reports (`app/controllers/reports_controller.rb:17`) `eval` code that only architects write; running reports is admin only.
- `users_controller.rb:65-67`: `admin`/`kiosk` only from admins, `architect` only from architects.
- Mailbox messages are framed with `sandbox` and no `allow-scripts` (`mailbox_messages/show.html.erb:10`).
- Copied blob links work for anyone for 1 hour (`config/application.rb:45-56`).
- JS libraries the importmap audit skips: FullCalendar 6.1.15, `@codemirror/legacy-modes` 6.4.0, Bootstrap 5.3.8: no advisories (OSV, 2026-11-28).

## Proposed fix

None expected. A failed check becomes its own item.

## Tests

- Paste the bypass variants into each Markdown field as the lowest role that writes it and open as a higher one: `[x](javascript:alert(1))`, `[x](JaVaScRiPt:alert(1))`, entity-encoded `javascript:`, a `data:text/html` link, `<img src=x onerror=alert(1)>`, `<svg onload=alert(1)>`, `![t](x" onerror="alert(1))`.
- As an admin without the architect flag: `POST /hooks` refused.
- As a student: `PATCH` own login with `user[admin]=1&user[architect]=1`: unchanged.
- Email with `<script>` and a meta refresh to the mailbox: nothing runs.
- Rerun the OSV query when any of those libraries changes.

## Fork strategy notes

Nothing to branch.
