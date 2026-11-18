# BL-052: Emails over the Resend rate limit are dropped

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | started (`feature/email-rate-limit-retry`) |
| Added | 2026-11-17 |
| Commit checked | `upstream/main` @ `eeaa691aa`; `app/jobs/send_email_job.rb` from `f3b42845a`, Resend gateway from `8e6135f03` |
| Planned branch | `feature/email-rate-limit-retry` |
| Upstream issue / PR | none |

## Summary

Resend allows 10 API requests a second. `SendEmailJob` (`app/jobs/send_email_job.rb:4-7`) calls `gateway.send_message` once per recipient and has no `retry_on`, so a burst of notices (for example several order requests submitted at once, each mailing every approver) fails some sends with `Resend::Error::RateLimitExceededError` (`app/models/gateway/resend_sending_gateway.rb:25`). The jobs land in Solid Queue's failed executions and the email is never sent. Seen on a production site: 5 of about 35 emails in one burst failed.

## Fix

- New `Gateway::RateLimited` error. Each sending gateway maps its own throttling error to it: Resend `RateLimitExceededError`, Postmark HTTP 429, SMTP `Net::SMTPServerBusy` (4xx).
- `SendEmailJob`: `retry_on Gateway::RateLimited, wait: :polynomially_longer, attempts: 10` (about 3 s, 18 s, 83 s, …), so throttled sends go out later; any other error fails as before.
- `SendEmailJob`: `limits_concurrency to: 1, key: "send_email"`, so the 3 worker threads can't send at once and most bursts stay under the limit.

## Tests

Job test: a gateway double that raises the rate-limit error once then succeeds; assert the job is re-enqueued and the second attempt sends. A different error is not retried.

## Fork notes

Edits an upstream file (`app/jobs/send_email_job.rb`): record it in `FORK.md` "Upstream files touched". Small and generic; a candidate for an upstream PR if Corey agrees.
