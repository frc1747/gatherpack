# BL-021: Remind opens a send screen: who it will email, and a message saved on the form

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | started: built on `feature/forms` (`db22e80`, `b9a6efe`); see `FORK.md` |
| Added | 2026-10-13 |
| Feature branch checked | `feature/forms` at `13e5a83` |
| Planned branch | change on `feature/forms` (no new branch) |
| Upstream issue / PR | none (forms isn't upstream) |

## Summary

A form's **Remind** button sends right away after a pop-up, and the email's wording is fixed. Two things went wrong in October 2026 with a leadership-retreat form meant for students but left open to students and guardians:

1. **The reach wasn't visible.** The button said "Remind (10)" and the pop-up said "for 10 people", and it sent 19 emails (10 students plus 9 guardians). The real count only appeared afterwards, in the flash. Each person got one email listing their students, so nothing was duplicated; the screen just counted students, not emails.
2. **The email couldn't say what the form was for.** A guardian got "Please complete **Form** by Oct 20 for: [student]" with an edit link, and completed it for their student. The sender had no way to say "students fill this in themselves; parents, just make sure it's done."

Decided with Corey (2026-10-13):

- Remind opens a send screen showing who it will email, with editable messages and a preview, like Slack's "This will notify N people" for `@everyone`.
- Each form remembers its messages, so the next reminder starts from what was sent last time. Duplicate copies them.
- The defaults are today's wording, so a form nobody customizes sends the same email it does now.
- Guardians get their own message, so a guardian's email can say "please remind them" instead of "please complete".
- **Form permissions stay as they are.** If the form lets guardians respond, the guardian's link still opens the form; if a parent fills it in, so be it. No new "remind only" setting.
- **"Also email guardians" tick box** (added 2026-10-13). The first reminder can go to the students alone, and a later one can add the guardian nudge. Untick it and guardians are left out, except where a guardian has to act (see below).
- **Guardian parts show only when guardians are involved.** If a send reaches no guardians, the screen, counts and preview say nothing about guardians. This applies to anything built on top of guardian relationships later: show the guardian part only when the operation actually reaches a guardian.

## Where things are (`feature/forms` `13e5a83`)

- `app/views/forms/show.html.erb:74-77`: `waiting` counts report rows (subjects); the button label and its `turbo_confirm` both use it.
- `app/controllers/forms_controller.rb:121-129`: `remind` builds the pending list from `FormReport` (rows not `complete` or `no_longer_asked`) and sends at once.
- `app/services/form_reminder_sender.rb`:
  - `:16-24` `recipients`: `{ recipient => [subjects] }`. The subject if `respond_permission` reaches `:subject` or their signature is outstanding; `subject.guardians` likewise for `:guardian`; people without an email dropped. A recipient is "themselves" when they're in their own subject list, otherwise a guardian. (A guardian who is also a waiting subject on the same form gets one email that lists "You" and their wards; treat them as themselves plus guardian, and use the guardian message, since it covers others.)
  - `:26-32` `send!`: one `SendEmailJob` per recipient, sets `last_reminded_at`, logs a `form_reminders` row with `recipient_count` and `filter`.
  - `:48-58` `body`: the fixed wording: "Hi {first name}," / "Please complete **{form}** by {date} for:" / a list of links, "You" or the subject's name, to the edit page, or the response page when a signature is outstanding.
- `app/views/forms/show.html.erb:88-89`: "Last reminder: … to N people" (uses `recipient_count`).
- `app/models/form.rb:293-300`: `duplicate!` uses `dup`, so new columns on `forms` are copied without changes there.
- `config/routes.rb:59`: `post :remind`.
- Markdown elsewhere: `Redcarpet::Markdown` with `Redcarpet::Render::HTML` (`app/helpers/application_helper.rb:101`, `app/services/announcement_notification_router.rb:9`).
- `Form.apply_schedule!` sends no email; Remind is the only path that emails a form's audience.
- Spec: `docs/forms-spec.md` §11.1 (Reminders), §3.8 (`form_reminders`).

## Proposed design

### Data

Add to `forms` (new migration, reversible):

- `reminder_message` (text, null): the message for people reminded about their own response.
- `guardian_reminder_message` (text, null): the message for guardians.

Null means "use the default". The defaults live in code and reproduce today's sentence:

- Themselves: `Please complete **{form}**{due} for:`
- Guardians: same text. Corey can then change it per form to a nudge, for example "**{form}** isn't finished yet{due}. Please remind them to do it:".

Add `guardian_count` (integer) and `guardians_included` (boolean) to `form_reminders` so the log line can say "19 people (9 guardians)" or "10 people, guardians not emailed". Optionally also store the message bodies sent, for the record.

### Message format

The editable part is Markdown with three placeholders, listed under the box in plain words: `{first name}`, `{form}`, `{due}` (" by October 20", or nothing if the form has no closing date). The email is:

1. "Hi {first name}," (fixed)
2. The message
3. The list of names with their links (fixed; unchanged from today)

The links and greeting stay outside the editable part, so a message can't lose the links. Escape the placeholder values before Markdown rendering (titles and names are user content).

### Send screen

`GET /forms/:id/remind` (new `remind_preview`, or make `remind` respond to GET) shows:

- The count, broken down only when guardians are included: "Email 19 people: 10 students and 9 guardians." With no guardians: "Email 10 people." (Say "people", not "students", when the subjects aren't all students; use the form's own subject wording if there is one.)
- An expandable list of who gets it, grouped the same way.
- **Message to people reminded about their own response** (text box prefilled with the saved message or the default).
- **Also email guardians** tick box, under the count: only when this send could reach at least one guardian. Ticking or unticking it updates the count, the list and the preview right away (a small Stimulus controller, or recount on the server through a Turbo Frame).
  - Default: unticked on the form's first reminder, ticked after that (any earlier `form_reminders` row). That matches "students first, then add the nudge"; the sender can always change it.
  - Guardians who have to act still get emailed when it's unticked: on a guardians-level form (subjects can't respond), or when a guardian's signature is outstanding. The screen says so: "2 guardians will still be emailed because they need to sign." In `FormReminderSender`, the box drops only the guardians added for a nudge (`respond_permission` reaches `:guardian` while the subject can act too); the `signers.include?(:guardian)` and guardian-only paths stay.
  - A subject with no email address gets no reminder while it's unticked. Say so in the count ("2 students have no email address and won't be reminded"), so ticking the box is the obvious fix.
- **Message to guardians**: only while the send includes at least one guardian (ticked, or guardians who have to act).
- A preview of one email of each kind that's going out, using a real recipient from the list.
- Above a threshold (about 25 emails), a stronger line: "This will email 60 people."
- **Send** and **Cancel**. No pop-up.

The **Remind (10)** button on the status page keeps the subject count and links to this screen, carrying the team filter.

`POST /forms/:id/remind` takes the messages, saves them to the form if they changed (that's what makes them stick), and sends. Keep the "Sent 19 reminders about 10 people" flash. If the message is cleared or matches the default, store null so later changes to the default still apply.

A "Reset to the default message" link next to each box.

### Hiding guardian parts

Decide from the actual recipients of this send, not from the form's permission setting alone. A form open to guardians can still have a send with no guardian recipients (every waiting subject has no guardian with an email). The guardian message box, counts and preview appear only when the send includes a guardian.

## Tests

- No customization: the email body matches today's output exactly (snapshot of `body` before and after).
- The send screen for a form open to subjects and guardians, with 2 waiting students who share one guardian and 1 with no guardian: "Email 4 people: 3 students and 1 guardian"; both message boxes; the guardian's email lists both students.
- A subjects-only form: no guardian wording, no guardian box, count "Email N people".
- A guardians-level form (guardians respond, subjects don't): only the guardian box.
- A send that reaches no guardians on a form that allows them: no guardian parts, no tick box.
- First reminder: the box starts unticked and only subjects are emailed; second reminder: it starts ticked. `form_reminders.guardians_included` records each.
- Unticked with an outstanding guardian signature: that guardian is still emailed and the screen says why; other guardians aren't.
- Guardians-level form: unticking can't leave a subject unreached (the box is hidden or forced on, since guardians are the only ones who can act).
- Unticked with a subject who has no email: the count names them as not reminded.
- Changing a message and sending saves it; the next send screen shows it; Duplicate copies it; Reset stores null.
- Placeholders fill in; a form title with `<script>` or Markdown characters is escaped.
- At or above the threshold, the stronger wording shows.
- The team filter carries from the status page to the send screen and into `form_reminders.filter`.
- Only someone allowed to Remind today can open the send screen (same policy as `remind`).

## Fork strategy notes

A change on `feature/forms` itself: a new migration (list it in `FORK.md`'s Migrations column), the send-screen view, and changes to `FormReminderSender`, `FormsController`, `config/routes.rb` (already in the forms row). Update spec §11.1 and §3.8 and the `FORK.md` notes when it lands. Sample data (`fork/sample_data/features/feature-forms.rb`) can give one form a custom guardian message.

`feature/signups` also emails groups (organizer "message a date", time-change notices). If those reach more than a handful of people, give them the same count, and guardian parts only when guardians are included, as a separate change on that branch.
