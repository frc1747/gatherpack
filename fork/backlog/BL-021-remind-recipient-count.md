# BL-021: Say how many emails Remind will send before it sends them

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-13 |
| Feature branch checked | `feature/forms` at `13e5a83` |
| Planned branch | change on `feature/forms` (no new branch) |
| Upstream issue / PR | none (forms isn't upstream) |

## Summary

A form's **Remind** button counts the people who still owe a response, not the emails it's about to send. On a form whose "who can respond" setting includes guardians, every waiting student's guardians get an email too. In October 2026 a leadership-retreat form meant for students only was left set to students and guardians: the button said "Remind (10)" and the confirmation said "for 10 people", and it sent 19 emails (10 students plus 9 guardians). Nothing on the screen said guardians would be emailed.

Each person already gets just one email that lists all their students, so this isn't about duplicate emails. The problem is that whoever sends the reminder can't see how far it will reach before clicking.

Slack does the same thing for `@everyone` in a large channel: "This will notify 214 people. Send anyway?"

## Where things are (`feature/forms` `13e5a83`)

- `app/views/forms/show.html.erb:74-77`: `waiting` counts report rows (subjects); the button label and `turbo_confirm` text both use it.
- `app/services/form_reminder_sender.rb:16-24`: `FormReminderSender#recipients` maps each recipient to their subjects: the subject if `respond_permission` reaches `:subject` (or their signature is outstanding), plus `subject.guardians` if it reaches `:guardian` (or theirs is). People without an email are dropped. Its `size` is the number of emails.
- `app/controllers/forms_controller.rb:121-129`: `remind` builds the same pending list from `FormReport` and sends. The flash afterwards does give the real count ("Sent 19 reminders about 10 people"), but only once they've gone out.
- `app/views/forms/show.html.erb:88-89`: "Last reminder: … to N people" uses `recipient_count` (emails), so it already reads differently from the button.
- `Form.apply_schedule!` (opening/closing on schedule) sends no email; Remind is the only path that emails form audiences.

## Proposed fix

1. In `show`, build `FormReminderSender.new(@form, pending)` for the same pending list and use `recipients` for the count. Its `outstanding_signers` lookups are per subject, so check the cost on a large form. If it's slow, add a count-only method that skips building the email bodies (it already does, since the body is built in `send!`).
2. The button keeps the subject count ("Remind (10)"). The confirmation states the emails and who gets them, in plain words:
   > Email 19 people: 10 students and 9 guardians? They're the people who haven't finished this form and those who can respond for them.

   Split the count into "themselves" (recipient is the subject) and "guardians" (everyone else), so the guardian part stands out.
3. Above a threshold (say 25 emails), make the warning stronger, the way Slack does for `@everyone`: "This will email 60 people." Keep it one confirm; no typed confirmation.
4. Optional: on the form's settings page, next to "who can respond", add a hint that Remind will email guardians as well when that option includes them. This is where the mistake actually happened.

## Tests

- A form open to subjects and guardians, with 2 waiting students who share one guardian and 1 with no guardian: the confirm text says 4 people (3 students, 1 guardian). The guardian gets one email listing both students.
- A subjects-only form: the confirm mentions no guardians.
- A form at or above the threshold shows the stronger wording.
- The flash after sending matches the number in the confirmation.

## Fork strategy notes

A change on `feature/forms` itself; update its `FORK.md` notes when it lands. `feature/signups` also emails groups (organizer "message a date", time-change notices). If those send to more than a handful of people, give them the same "this will email N people" confirmation, as a separate change on that branch.
