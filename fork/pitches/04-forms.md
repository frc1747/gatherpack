# Forms

## Summary

Leaders ask a group of people for information or a signature by a
deadline, and see who has answered, who answered for whom, who signed,
and exactly what was signed. Requires person fields.

## Problem

Three common needs are handled today with spreadsheets, paper, and group
chats:

- **Season preferences.** Meal choices, shirt sizes, allergies, collected
  once and used at many events. Spreadsheets have blank rows, nothing
  tracks who still owes an answer, and allergies end up in a second place
  from the profile.
- **Consent and acknowledgments.** Parent consent, permission slips, code
  of conduct, photo release: the right person has to sign, there has to
  be a record, and it has to be renewed when something changes.
- **Event intent.** "Coming Saturday?" as a planning count, kept separate
  from attendance; check-ins remain the record of who came.

## What it does

- **No form types.** Behavior comes from what is on the form (a signature
  question, a linked event, a completion badge), so the same building
  blocks serve a sign-up sheet, a waiver, or a t-shirt order.
- **Audiences** are built from teams, badges, and individual people, with
  exclusions. Outstanding forms appear on the dashboard and on a Forms
  tab on the profile.
- **Guardians answer for their children**, using person fields'
  guardianship. Each signature question sets who signs: the person, a
  guardian, or a guardian only if the person is a minor. A leader can
  record a paper signature.
- **Questions can link to the profile.** Each question is form-only,
  filled in from the profile, or updates the profile when submitted
  (through person fields' write rules), so data like allergies lives in
  one place.
- **Every answer is kept.** A response is a history of submissions; the
  latest fully signed one is active. Each submission keeps a copy of the
  form's text as signed. Changing a published form's text can require
  fresh signatures.
- **Profile changes flagged.** If a profile value a signed form relied on
  changes, the form shows it and can require re-confirmation.
- **Completion badges.** Finishing a form can award a badge (for example
  "Consent Signed") for other features and reports to use.
- **Reports:** a status page (who still owes an answer, with a Remind
  button), a results grid with profile columns and CSV export, a tally,
  and a printable list for orders and packing lists that can combine
  answers across forms.
- **Events.** A form can attach to an event, with an intent question and
  an "expected vs. checked in" view on the event page.
- **Permissions** use the same levels as person fields, per form and per
  question. Admins and team managers create forms. Optionally, holders of
  a chosen badge can create simple event polls for their own teams.
- **Hooks** for form, response, and completion events.

## How it's built

- Almost all new files. Eleven reversible migrations, all new tables or
  new columns on them.
- Behind a feature flag, off by default. A scheduled job opens and closes
  forms and does nothing while the flag is off.
- **Footprint:** 12 existing upstream files, mostly one line each for a
  dashboard card, a profile tab, an event page panel, hook events, and
  routes. The rest are files person fields already touches.
- An add-on, unlike person fields. With small generic extension points
  (slots for dashboard cards, profile tabs, and event page panels; hook
  event registration; feature routes) it could live almost entirely in
  its own files.

## Adoption

Follows the person fields decision. With person fields (or an
equivalent) in core, forms can follow as a feature PR. Without it, the
extension points above keep forms nearly self-contained.

Not built yet: automatic reminders, reminders at the time kiosk, file
uploads (such as insurance cards), conditional questions, and linking a
form to a payment.
