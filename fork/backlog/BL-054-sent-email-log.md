# BL-054: Sent email log, with delivery and link clicks

| | |
|---|---|
| Kind | fork-only (feature) |
| Priority | medium |
| Status | shipped hbr.54 |
| Added | 2026-11-17 |
| Commit checked | `upstream/main` @ `eeaa691aa`; Resend gateway from `8e6135f03`; order notices from `feature/orders` (hbr.48) |
| Planned branch | `feature/email-log` (core); the order request part on `feature/orders`, depending on it |
| Upstream issue / PR | none |

## Summary

GatherPack forgets every email once it's handed to the sending service. Admins can't answer "did they get it?", and an approver can't tell whether the other approvers saw a request. The sending services already know: Resend and Postmark report delivery, bounces and (with click tracking on) link clicks through webhooks. GatherPack receives those webhooks today but ignores them.

This adds a log of every email GatherPack sends, updates each entry from the service's webhooks, and shows it in two places:

1. **Sent email** screen for admins: every send with its status (sent, delivered, bounced, complained, failed) and first link click.
2. **On the record the email was about**, starting with order requests: under each approval step, "Link clicked 8:26 PM" beside each approver who was emailed.

## Evidence

- `SendEmailJob#perform` (`app/jobs/send_email_job.rb:10-12`) calls `gateway.send_message` and drops the result. Resend returns the message id (`Resend::Response data={id: …}`, seen on prod); Postmark returns `MessageID`.
- `Gateway::ResendSendingGateway#finish_setup` (`app/models/gateway/resend_sending_gateway.rb:60-71`) subscribes only to `email.bounced` and `email.complained`, and `#handle_webhook` (`:37-58`) leaves both branches empty. Postmark (`postmark_sending_gateway.rb:38-51`) is the same.
- Every notice sender queues `SendEmailJob.perform_later(gateway, address, subject, body)` with nothing saying who or what it's for (`app/services/order_notices.rb:146-155` on `feature/orders`, `signup_notices.rb`, `deliver_daily_digests_job.rb:38`, `devise_gateway_mailer.rb`, `infodump.rb:65`, `commitments/message.rb:22`).
- With Resend click tracking on, delivered HTML links go through a tracking subdomain (`https://l.<sending domain>/CL0/<url>/…`), and Resend logs a `clicked` event with the reader's browser (checked with a test send on a production site).

## Design

**Log table** `sent_emails`: `gateway_id`, `person_id` (nullable), `address`, `subject`, `about` (polymorphic, nullable), `provider_message_id` (unique per gateway), `status`, `sent_at`, `delivered_at`, `problem_at`, `problem_detail`, `first_clicked_at`, `click_count`, `first_clicked_url`, `opened_at`. No body, IP address or browser: the subject and times answer the question, and many recipients are students. Statuses are tied to code, so they stay in code with editable labels.

**Sending.** `SendEmailJob#perform(gateway, address, subject, body, person: nil, about: nil)`: keyword arguments, so every existing call keeps working. It creates the row before sending, stores the id `send_message` returns (each gateway returns it as a string; SMTP returns nil), and marks `failed` with the error when the job gives up. Callers that know the person and the record pass them; order notices, sign-up notices and digests are updated in this item, the rest log with address only.

**Webhooks.** A new `Gateway#record_delivery_event(provider_message_id, kind, at:, url: nil, detail: nil)` updates the row; unknown ids are ignored. Resend maps `email.delivered`, `email.bounced`, `email.complained`, `email.clicked`, `email.opened`; Postmark maps `Delivery`, `Bounce`, `SpamComplaint`, `Click`, `Open`. `finish_setup` subscribes new gateways to all of them. An existing gateway keeps its webhook, so the gateway page gets an **Update webhook events** button that re-registers it (Resend: update the webhook by id when it's found by URL, else create one and save the new signing secret). The empty "disable notifications" branches stay as they are: suppressing sends after a bounce is separate work.

**Clicks are not reads.** Screens say "Link clicked", never "read" or "seen". Mail scanners (school and company filters) sometimes follow links on delivery, so a click within the first 10 seconds after `delivered_at` is recorded but not shown as a person's click (a setting, `email_log_scanner_seconds`, default 10).

**Sent email screen** (Setup → Email → Sent email, admins only): newest first, filters for person, status and "about", search by address or subject. Columns: When, To, Subject, Status, Link clicked. Each row links to the person and the record it was about. A person's page gets a "Sent email" link to the same list filtered to them, shown to admins.

**Order requests** (`feature/orders`): on the request page, each approval step lists the approvers emailed for it with "Emailed 8:19 PM · Link clicked 8:26 PM" (or "Emailed, not clicked yet"), visible to people who can approve or manage the request. It reads `sent_emails` where `about` is the request.

**Retention:** a daily job deletes rows older than `email_log_keep_days` (setting, default 180).

**Flag:** `feature_email_log`, off by default. Off: no rows written, no screens, webhooks behave as today.

**Hooks:** none. The log is a record of sends, not something other features act on.

## Tests

- Job: creates a row, stores the returned id, marks `failed` after the last retry; existing four-argument calls still work.
- Resend and Postmark: each mapped webhook payload updates the right row; an unknown id is ignored; a signed request is still required.
- Scanner window: a click 3 s after delivery is stored but not shown; one at 60 s is shown.
- Sent email screen: admins only; filters; a non-admin gets 403 (or the usual redirect).
- Order request page: approver lines show emailed and clicked times; people who can't approve don't see them.
- Retention job deletes only rows past the setting.
- Flag off: nothing logged, screens hidden.

## Fork notes

- Upstream files touched: `app/jobs/send_email_job.rb`, the three sending gateways, `app/views/gateways/show.html.erb` (the button). Record them in `FORK.md`. `send_email_job.rb` is also changed by `feature/email-rate-limit-retry` (BL-052): base this branch on it or resolve at sync.
- New migration (reversible), no edits to upstream migrations.
- Turning on clicks in production also needs click tracking on the sending domain (already on for HBR's Resend domain).

## Built

- Core log: task 385 on `feature/email-log`, commits `7fe6dd923` and `5c58296fb` (query strings stripped from stored links, retention job `DeleteOldSentEmailsJob` with `email_log_keep_days`, settings and routes through the seams).
- Order request part: task 386 on `feature/email-log-orders`, commits `33fc6732b` and `0445ca531`. Depends on `feature/email-log` and `feature/orders`.
- The row stays `started` until a release ships them.

## Deferred

- The person page's "Sent email" link (`people/show`). The filtered list already works at `/sent_emails?q[person_id_eq]=<id>`.
- Passing `person:` and `about:` from sign-up notices and the summaries (digests); only order notices pass them so far.
- The order request panel infers which step an email counts for from timing, with two edge cases: re-approval ("Approve again") emails are sent after the final approval, so they don't appear; and a job that runs very late could be counted under the next step. Storing the step (or a notice kind) on the log row needs a column in the core log.
- Postmark sends still have open and link tracking off, so Postmark click and open events are mapped but won't arrive until sending turns tracking on.
