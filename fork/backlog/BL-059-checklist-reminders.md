# BL-059: Checklist reminders, with items and fields that never go in an email

| | |
|---|---|
| Kind | fork-only (feature) |
| Priority | medium |
| Status | done (feature/checklists-reminders + feature/person-fields, not yet released) |
| Added | 2026-11-21 |
| Commit checked | `feature/checklists` @ `9bb274287`, `feature/person-fields` @ `b5aed6cbe` |
| Planned branches | new `feature/checklists-reminders`; a small change on `feature/person-fields` |
| Upstream issue / PR | none |

## Summary

Organizers can't remind people what's left on a checklist. Today they copy names out of the report and write emails by hand. Add reminders: an organizer sends them from the checklist (and can schedule them), to each person who isn't Complete, and optionally to their guardians.

The catch is that some checklist items are about records that mustn't travel by email. A school team's academic eligibility item reads a grades field, and student education records shouldn't be sent in email to students or guardians. Other groups (a 4-H club, a scout troop) have no such rule and want the full detail in the email. So GatherPack doesn't learn any particular law. It gets one general control, **what an email may say**, set on the data and on the checklist, and always applied in the strictest direction.

## Evidence

- No reminder or email code in checklists: `app/models/checklist*.rb`, `app/controllers/checklist*` (`feature/checklists` @ `9bb274287`). The spec rules out one automatic case only, Complete → Not Started (`fork/specs/checklists-spec.md` §15 decision 25).
- Item text carries the data. `app/models/checklists/kinds/person_field.rb:313-322` builds summaries and details from the field's name and test, e.g. "No <field> on file", "<field> hasn't been updated since <date>". The item's own label ("Passing all classes") and even the checklist's name ("Academic Eligibility") say something about the person when paired with "Not Started".
- `PersonField#read_permission` (`app/models/person_field.rb`, `feature/person-fields` @ `b5aed6cbe`) says who may *see* a field on the site. Nothing says whether it may leave the site. A family-readable field can be one a guardian may see when signed in but shouldn't get by email.
- Existing reminder patterns to copy: `FormAutoReminderJob` and the form reminder messages (`feature/forms-auto-reminders`, `feature/forms`), digest sections (`GatherPack::Digests.register`, `feature/digests`), and push connectors that follow emails (`feature/phone-notifications-connectors`).

## What it does

### 1. One rule: what an email may say

Three levels, used everywhere below. The words are tied to code, so they're a fixed list with editable labels.

| Level | In the email |
|---|---|
| **Everything** | The item's name, its status and its summary ("No shirt size on file"), plus a link to fix it. |
| **Name only** | The item's name and status, no summary or detail. |
| **Just "sign in"** | Not named. It's counted: "1 more item. Sign in to see it." |

Three places set it, and **the strictest wins**:

1. **Profile field:** a new tick box on each person field, **"Keep out of email and notifications"** (off by default). An item that reads a ticked field (`person_field` kind, or an `any_of` that contains one) is held at **Just "sign in"** and its editor can't raise it. The tick box belongs to the field, not to checklists, so any other feature that emails field values (form reminders, digests, push) can honor the same flag later.
2. **Checklist:** **"What reminders may say"**, default **Everything**. It's the most any of its items may say. At **Just "sign in"**, the email doesn't name the checklist either: "You have items to finish in GatherPack. Sign in to see them."
3. **Item:** the same choice, default "Same as the checklist", and can only lower it.

The checklist editor shows the result by each item ("Email: name only, because it reads Grade Point Average, which is kept out of email"), and the reminder preview (§2) shows the exact email, so an organizer never has to guess.

Decisions:
- **No law named in the product.** The control is "keep out of email", which a school uses for education records, a club for medical notes, and most groups not at all. HBR's FERPA reasoning lives in HBR's configuration, not in code or copy.
- **The data wins over the checklist.** Someone who makes a checklist can't override a field an admin marked as kept out of email.
- **Status counts as data.** "Not Started" next to a named academic item says the person isn't eligible, so the strict level hides the name, not just the detail.
- **The same rule applies to push notifications** sent by the phone-notifications connector, and to anything the sent email log (BL-054) stores about the message.

### 2. Sending

On the checklist's report, organizers (and anyone who runs it, checklists spec §10.1) get **Send Reminder**:

- **Who to remind:** everyone not Complete (default), or the people ticked in the report. Exempt and excused people are never included.
- **Also send to guardians** tick box (off by default). Guardians get the same email about their ward, but only the items the guardian could see on the site (an item at `self_and_leaders` stays out of a guardian's email). A guardian with several wards on the checklist gets one email.
- **A note** from the organizer, added above the list (plain text, optional).
- **Preview** shows the exact email for one chosen person (and their guardian, when ticked), with the levels applied, before **Send**.

**Scheduled reminders** on the checklist's Setup tab: off by default; when on, "every N days" to people not Complete, optionally "and N days before the checklist ends", with the same guardian tick box. Each person gets at most one checklist reminder a day across all checklists; several due on one day go in one email. If `feature/digests` is on, the checklist can send through the person's digest instead (a registered section), using the person's own delivery choice.

Each send is recorded (`checklist_reminders`: checklist, sent by, sent at, recipient count, scheduled or by hand) and shown on the checklist's Setup tab as "Last reminder sent…". The record keeps counts, never the email body.

## Build

- **`feature/person-fields`:** migration `add_keep_out_of_email_to_person_fields` (boolean, default false, reversible); tick box on the field form with the hint "Values and anything about this field stay on the site. Emails and notifications only say to sign in."; `PersonField#keep_out_of_email?`. Behind `feature_person_fields` like the rest of custom fields; off by default means nothing changes.
- **`feature/checklists-reminders`** (depends on `feature/checklists-connectors` for the `person_field` kind, and `feature/recurring-routes-seams`):
  - Columns: `checklists.email_level`, `checklist_items.email_level` (null = same as the checklist), schedule columns on `checklists`; table `checklist_reminders`.
  - `ItemKind.email_ceiling(item)`, default Everything; the `person_field` kind returns Just "sign in" when its field is kept out of email; `any_of` returns its strictest child's. `Checklists::EmailLevel.for(item)` = strictest of field, item, checklist. One method used by the mailer, the push connector, the editor note and the preview, so they can't disagree.
  - `ChecklistReminderMailer`, `ChecklistReminderJob` (recurring, in `config/recurring.d/`), `Checklists::ReminderBuilder` (who gets what, guardian filtering through `Checklists::Visibility`).
  - Flag `feature_checklist_reminders`, off by default.
- Hooks: `checklist_reminders - created` on each send (counts only, no item text). The new columns on person fields and checklists ride their models' existing hooks.

## Tests

- Level: field ticked → item at Just "sign in" whatever the item and checklist say; checklist at Name only caps an item at Everything; an item can lower, not raise; `any_of` with one ticked field child is held at Just "sign in".
- Mailer: at each level the email contains exactly the parts in §1's table; at checklist Just "sign in" neither the checklist name nor any item name appears; field names and values from `person_field` summaries never appear for a ticked field (assert on the rendered body).
- Recipients: Complete, exempt and excused people get nothing; guardians only when ticked; guardians don't get items they can't see; a guardian with two wards gets one email; one email per person per day across checklists.
- Push connector follows the same levels.
- Preview equals what's sent.
- Flag off: no button, no schedule, job does nothing.

## Fork notes

Fork-only: checklists, person fields, digests and push are all fork features. No upstream files touched beyond `db/schema.rb`. The person-fields tick box is a separate small change on `feature/person-fields` because the flag describes the field, not the checklist.

For HBR, after release: tick "Keep out of email and notifications" on the grades fields, set the academic eligibility checklist's "What reminders may say" to Just "sign in", and leave other checklists at Everything.
