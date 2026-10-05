# Spec: Forms (data requests, consent, and event intent)

Status: **Draft for review.** Builds on `feature/person-fields` (issue #489):
its permission levels, badge grants, guardianship, and field types.
Date: 2026-10-05 (rev. 2: every answer is kept on the form; responses are a
history of submissions with one active, signed version; questions choose how
they relate to the profile)

## 1. Goal

Let leaders ask a defined group of people for information, by a deadline,
with a clear record of who has answered, who answered for whom, who signed,
and what exactly they signed. One mechanism covers:

- **Season preferences.** The 2026-27 Meal Choices spreadsheet: a sandwich
  choice per restaurant, toppings to remove, a cookie, a chip, two entrées, a
  wishlist, and allergies, collected once and used at many events.
- **Consent and acknowledgment.** Parent consent, travel permission slips,
  code of conduct, photo release: a statement, a signature from the right
  person, and proof that it happened, renewed when something changes.
- **Event intent.** "Are you coming Saturday?" as a planning count. It is
  **never** attendance (§10).

The spreadsheet shows what goes wrong today: a third of the rows are blank
and nothing tracks who still owes an answer; the same choice is typed several
ways ("Choc. Chip", "Choc.Chip", "DoubleChoc."); allergies are kept in a
second place from the profile's Dietary Restrictions; and turning the answers
into an order ("Jimmy John's: 4× Slim 4, 2× Big John") is done by hand.

### 1.1 The model in four sentences

1. A **form** is a request: an audience, a deadline, who may answer, who may
   see, and a list of questions.
2. **Every answer is kept on the form.** A submission records exactly what
   was submitted and signed, whatever happens to the profile afterwards.
3. Each question chooses its relationship to the profile: **form only**,
   **filled in from the profile**, or **updates the profile** (§3.3).
4. A person's response is a **history of submissions**. One of them is
   **active**: the latest one that is fully submitted and signed. Updating
   starts from the active answers and needs fresh signatures; until those
   arrive, the previous signed version stays active. **Reports read the
   active version, alongside current profile data** (§9).

### 1.2 Non-goals (v1)

- **Locking profile fields** to a form. Profile data stays editable through
  its normal rules; a form detects and flags changes since it was signed
  instead (§8).
- **Conditional logic** ("show question 5 if question 4 is Yes"). §15.
- **Payments** attached to a form (trip fees). A later phase can link a
  submission to a ledger entry.
- **Anonymous or public forms.** Every response is about a known person, and
  the respondent is signed in.
- **Several independent responses per person per form.** A person has one
  response per form, with a history of versions. A new season or trip is a
  new form; Duplicate makes that cheap (§12.2).
- **Legal advice.** The signature design (§7) follows common e-signature
  practice (intent, attribution, record keeping). Whether it suffices for a
  given document is the organization's decision.

---

## 2. What exists today (and what we reuse)

| Piece | Where | How Forms uses it |
|---|---|---|
| Permission levels `admin`, `self`, `leaders`, `self_and_leaders`, `guardians`, `family`, `team`, `everyone`, stored as explicit integers | `PersonField::PERMISSION_LEVELS`, `LEVEL_VALUES` | The same levels, the same integers, for who may answer and who may see (§5) |
| Single-subject evaluator and list form | `AudienceAccess`, `AudienceLevels.people`, `.component_people`, `PersonField#subjects_for` (§2.1) | The same audience components (`subject`, `guardian`, `leaders`, `teammates`, `everyone`) |
| Badge grants (only admin-assigned badges; team badges scope the grant) | `PersonFieldBadgeGrant` | `FormBadgeGrant`, same rules (§5.3) |
| Guardianship (typed, directed, age-limited) | `Relationship.active_guardianships`, `Person#guardians`, `#wards` | Who may answer for whom, and who must sign (§7) |
| Field types, choice lists, normalization, casting | `PersonField` `data_type`, `options`, `#normalize`, `#cast`, `#serialize` | Form-only questions use the same types and code (§3.2) |
| Writing profile data on someone's behalf | `Person#assign_field_values(values, acting:)` | "Updates profile" questions apply through it when a submission becomes active, so person field write rules and the `person_fields - value changed` hook apply unchanged (§6.4) |
| Profile change notifications | `person_fields - value changed` (`PersonFieldChange`) | Detecting profile changes since signing (§8) |
| Applicability by team subtree | `PersonField#applies_to?`, `Team#descendant_people` | Form audience (§3.1) |
| Badges as the record of a status | Safety badge, "2027 FIRST Consent Signed" | Completion badge (§8.3) |
| Admin-authored dynamic Pages (ERB) | `Page` (`dynamic`, editor must be `admin`) | Custom reports over active answers through a permission-aware reader (§9.5) |
| Email | `SendEmailJob`, sending gateways | Reminders (§11) |
| Scheduled jobs | Solid Queue, `config/recurring.yml` | Opening and closing forms (§11.3) |
| Feature registration | `GatherPack::Features.register_built_in` | `:forms`, off by default |
| Check-ins as attendance | `Checkin`, `Event#checkins` | Read only, to compare intent with attendance. Forms never create one (§10) |

### 2.1 Shared pieces (phase 0, done)

Done on `feature/person-fields` in `5b2700a` (2026-10-05), with no behaviour
change, so Forms reuses the same code rather than copying it:

- `AudienceLevels` (`app/models/audience_levels.rb`, a module):
  `PERMISSION_LEVELS`, `LEVEL_VALUES`, `.reaches?(level, component)`,
  `.within?(inner, outer)` (the containment test), `.people(level, viewer)`
  (formerly `PersonField.level_people`), `.relations`, `.component_people`,
  and `.combine` (one `Person` relation from several).
- `AudienceAccess` (`app/models/audience_access.rb`): one viewer's audience
  components relative to one subject, with each lookup cached.
  `PersonFieldAccess` subclasses it; `FormAccess` (§5.3) will too.
- `FieldValueType` (`app/models/concerns/field_value_type.rb`): the
  `data_type` enum, `options` accessors, `normalize`, `cast`, `serialize`,
  `choice_list`, and the option validations. `FormQuestion` includes it.

---

## 3. Data model

Seven new tables.

```
badges ──< form_badge_grants >──┐
                                │
teams ──< forms >───────────────┼──< form_questions >── person_fields (optional)
events ─<┘                      │
                                └──< form_responses ──< form_submissions ──< form_signatures
                                       │  (one per        (numbered history;
                                       │   subject)        one active)
                                    subject (people)
                                       └──< form_reminders
```

Terms used below:

- **Response**: one person's (the *subject's*) record for one form.
- **Submission**: one version of that response's answers. Numbered 1, 2, 3…
- **Active submission**: the response's latest submission that has been
  submitted and fully signed. Reports read it.

### 3.1 `forms`, neat_id prefix `frm`

| Column | Type | Notes |
|---|---|---|
| `title` | string, required | |
| `key` | string, required, unique, `\A[a-z][a-z0-9_]*\z` | Stable name for reports, hooks, and Pages (`meal_choices_2027`). Generated from the title, immutable after create |
| `description` | text | Markdown, shown at the top (Redcarpet, as announcements) |
| `team_id` | uuid, FK, required | Owning team. **Audience** is people with a direct membership in this team or a descendant (`team.descendant_people`) |
| `audience_badge_id` | uuid, FK, nullable | Narrows the audience to holders of this badge |
| `event_id` | uuid, FK, nullable | An event form (§10). The event's team must be the form's team or inside it |
| `kind` | integer enum | `general: 0, consent: 1, event_intent: 2`. Presentation and defaults only |
| `respond_permission` | integer enum (`LEVEL_VALUES`) | Who may fill in and submit for a subject. Default `family` |
| `read_permission` | integer enum (`LEVEL_VALUES`) | Who may see a subject's response. Default `family` |
| `status` | integer enum | `draft: 0, open: 1, closed: 2, archived: 3` |
| `opens_at`, `closes_at` | datetime, nullable | Automatic transitions (§11.3). `closes_at` is the deadline shown everywhere |
| `allow_updates` | boolean, default true | Respondents may submit a new version after their first one, while the form is open |
| `late_entry` | integer enum | Who may still submit after close: `none: 0, leaders: 1` (default `leaders`, for paper forms handed in late) |
| `version` | integer, default 1 | Form content version, bumped by Publish changes (§7.4) |
| `reconfirm_on_profile_change` | boolean, default false | A change to profile data this form updated sends the response back for re-confirmation (§8.2) |
| `completion_badge_id` | uuid, FK, nullable | Held while the response is complete (§8.3). Admin-assigned badges only |
| `created_by_id` | uuid → people | |

Validations: `respond_permission` ⊆ `read_permission` (as person fields);
`closes_at > opens_at`; the completion badge is `added_by_admin?`, and if it
has a team, that team contains the form's team (otherwise some of the
audience could never hold it, since `BadgeAssignment#team_membership`
refuses).

### 3.2 `form_questions`, prefix `frmq`

| Column | Type | Notes |
|---|---|---|
| `form_id` | uuid, FK, required | |
| `position` | integer | Order |
| `kind` | integer enum | `input: 0, heading: 1, statement: 2, acknowledgment: 3, signature: 4, intent: 5` |
| `label` | string | Required except for `heading`/`statement` with a body |
| `body` | text | Markdown: help text, the statement, or the acknowledgment sentence |
| `key` | string | Unique per form, `\A[a-z][a-z0-9_]*\z`, generated from the label, immutable once answered. Answers are keyed by it |
| `data_type`, `options` | as `PersonField` (`FieldValueType`) | For form-only `input` questions. The meal choice lists live here |
| `person_field_id` | uuid, FK, nullable | For profile-backed `input` questions (§3.3). The question then takes its type and choices from the person field |
| `profile_mode` | integer enum, nullable | `prefill: 0, update_profile: 1`. Required when `person_field_id` is set, null otherwise |
| `required` | boolean | |
| `read_permission`, `write_permission` | integer enum, **nullable** | Per-question overrides (§5.2). Null = inherit the form's levels |
| `signer` | integer enum | For `signature` only: `subject: 0, guardian: 1, guardian_if_minor: 2, leader: 3` (§7.1) |

| Kind | Answer | Use |
|---|---|---|
| `input` | A typed value | Sandwich choice, "Please Remove" (multi-select), allergies (profile-backed) |
| `heading` | none | Section title ("Jimmy John's") |
| `statement` | none | Text the respondent reads (trip details, the release) |
| `acknowledgment` | boolean, must be true if required | "I have read the code of conduct" |
| `signature` | a `form_signatures` row (§7) | Parent consent |
| `intent` | `yes`/`no`/`maybe` | Event intent (§10). At most one per form |

### 3.3 How a question relates to the profile

Chosen per question by whoever builds the form. **Form only** is the
default; changing the profile is always an explicit choice.

| Mode | Columns | Starting value | On activation | Example |
|---|---|---|---|---|
| **Form only** | no `person_field_id` | The previous active submission's answer, else blank | Nothing outside the form | Sandwich choice, "anything else about this trip?" |
| **Filled in from profile** | `person_field_id`, `profile_mode: prefill` | The previous active submission's answer, else the current profile value | Nothing outside the form. The person may change it for this form only | Trip form showing the emergency contact; the parent writes "grandma this weekend" without changing the profile |
| **Updates profile** | `person_field_id`, `profile_mode: update_profile` | The **current profile value** (it is the source of truth), with a note if it differs from what was last signed | The answer is written to the profile (§6.4) | Yearly "check your family's info" form; a medical form that is the official source for allergies |

In every mode the answer is also stored in the submission, so the form
always shows what was submitted and signed.

### 3.4 `form_responses`, prefix `frmr`

One per form and subject: the envelope for the submission history.

| Column | Type | Notes |
|---|---|---|
| `form_id` | uuid, FK, required | |
| `subject_id` | uuid → people, required | Who the response is about |
| `active_submission_id` | uuid → form_submissions, nullable | The version reports read |
| `status` | integer enum | Cached summary, recomputed by `#sync_status!` (§8.1): `draft: 0, waiting: 1, complete: 2, needs_reconfirmation: 3, withdrawn: 4` |
| `update_in_progress` | boolean | A draft or pending submission exists alongside an active one |
| `last_reminded_at` | datetime | |
| | | Unique index on `(form_id, subject_id)` |

Created lazily, on the first save. "Not started" is the absence of a row.

### 3.5 `form_submissions`, prefix `frmsb`

Immutable once submitted, except for its status.

| Column | Type | Notes |
|---|---|---|
| `form_response_id` | uuid, FK, required | |
| `number` | integer | 1, 2, 3… per response |
| `status` | integer enum | `draft: 0, pending: 1, active: 2, superseded: 3, withdrawn: 4, discarded: 5` |
| `answers` | jsonb, default `{}` | Every question's answer (all three profile modes, acknowledgments, intent), keyed by question `key`, serialized by the question's type |
| `form_version` | integer | The form version it was started on, refreshed on submit |
| `based_on_id` | uuid → form_submissions, nullable | The active submission this one started from |
| `created_by_id`, `submitted_by_id` | uuid → people | Who started it and who pressed Submit (subject, guardian, or leader) |
| `submitted_at`, `activated_at` | datetime | |
| `entered_late` | boolean | Submitted after close via `late_entry` |
| `profile_skipped` | jsonb, default `[]` | "Updates profile" keys that couldn't be written on activation (§6.4) |
| | | Partial unique indexes: one `active`, and one `draft`-or-`pending`, per response. GIN index on `answers` |

Why jsonb rather than an EAV table like `person_field_values`: answers live
and die with their submission; a signature covers the submission as a whole;
no query needs one row per value across forms; and tallies work with
`answers->>'key'`.

### 3.6 `form_signatures`, prefix `frms`

| Column | Type | Notes |
|---|---|---|
| `form_submission_id` | uuid, FK, required | Signatures belong to a submission and never carry over to the next |
| `form_question_id` | uuid, FK, required | The `signature` question |
| `signer_id` | uuid → people, required | |
| `signer_role` | integer enum | `subject: 0, guardian: 1, leader: 2`: the role that qualified them |
| `typed_name` | string, required | Must match the signer's name (§7.2) |
| `signed_at` | datetime | |
| `content_digest` | string | SHA-256 over the form version's rendered text **and** the submission's answers (§7.3) |
| `ip_address`, `user_agent` | string | Attribution |
| `revoked_at`, `revoked_by_id`, `revoked_reason` | | Revocation keeps the row |

### 3.7 `form_badge_grants`, prefix `frmbg`

| Column | Type | Notes |
|---|---|---|
| `form_id`, `badge_id` | uuid, FK, required | Unique together |
| `access` | integer enum | `read: 0, respond: 1`; `respond` implies read |

Same rules as `PersonFieldBadgeGrant`: admin-assigned badges only; a team
badge covers only subjects in that team's subtree. Use: a "Meal Coordinator"
badge sees every meal response without being a team manager; a "Travel
Coordinator" enters paper permission slips.

### 3.8 `form_reminders`, prefix `frmrm`

`form_id`, `sent_by_id`, `sent_at`, `recipient_count`, `filter` (jsonb). A
log of Remind presses (§11.1), so leaders can see when the last nudge went
out.

---

## 4. Lifecycle of a response

```
                start / update
   (none) ───────────────────────▶ draft ──discard──▶ discarded
                                     │
                                  submit
                                     ▼
                          ┌──── pending ────── discard / edit revokes signatures
      no signatures       │          │
      required ───────────┘   all required signatures
                                     ▼
                                   active ──── a newer one activates ───▶ superseded
                                     │
                                 withdraw
                                     ▼
                                 withdrawn
```

1. **Start.** The respondent opens the form for a subject. A `draft`
   submission is created on first save, with starting values per §3.3.
2. **Submit.** Required questions the respondent can write are validated.
   With no signature questions, the submission becomes `active` at once.
   Otherwise it becomes `pending` until every required signature is present.
3. **Sign.** Each required signature question is signed by an eligible
   signer (§7.1). The last one activates the submission.
4. **Activate.** In one transaction: the previous active submission becomes
   `superseded`; this one becomes `active` and the response points to it;
   "updates profile" answers are written to the profile (§6.4); the response
   status and completion badge are re-synced (§8).
5. **Update.** With `allow_updates` (or as a leader with `late_entry`), the
   respondent chooses **Update**. A new draft is created from the active
   submission (`based_on_id`), with starting values per §3.3, **and no
   signatures**. Submitting it requires fresh signatures. Until it
   activates, the previous submission stays active: reports, badges, and
   order sheets keep using it, and the response shows "Update in progress".
6. **Edit while pending.** Changing a pending submission's answers returns it
   to `draft` and revokes any signatures already on it ("Answers changed
   after signing"), because they signed different content.
7. **Discard.** A draft or pending submission can be discarded by its
   creator or a leader. The active one is unaffected.
8. **Withdraw.** Respondents and leaders can withdraw the active submission.
   It becomes `withdrawn`, its signatures are revoked, the response has no
   active submission, and the badge comes off. Profile values it wrote are
   **not** rolled back: they may have been edited since, and the audit log
   has the history.

The response page lists every submission with its number, who submitted,
who signed, its status, and a diff against the one before.

---

## 5. Permissions

The rule: **form permissions work like person field permissions; members
fill in their own forms; guardians and leaders can be brought in.**

### 5.1 Form levels

Two levels on the form, from the person field level table, relative to the
**subject**:

- `respond_permission`: who may start, edit, submit, update, and discard
  the subject's submissions.
- `read_permission`: who may see the response and its history. `respond` ⊆
  `read`.

| Respond level | Who can answer for a student | Typical form |
|---|---|---|
| `self` | the student only | Personal survey |
| `self_and_leaders` | the student, or a leader entering it | Meal choices without parents |
| `family` (**default**) | the student, a guardian, or a leader | Meal choices, most forms |
| `guardians` | a guardian or a leader, not the student | Medical history |
| `leaders` | leaders only | Leader checklist about a student |

Read works the same way. `team` read lets teammates see each other's answers
(shirt sizes for a group order); the default `family` keeps answers between
the student, their guardians, and their leaders. Admins pass every check.

### 5.2 Per-question rules

A form can have a student part and a parent part, or a leader-only part.

- **Form-only questions, acknowledgments, signatures** may override
  `read_permission` (must be ⊆ the form's read level: a question can be more
  private than the form, never more public) and `write_permission` (must be ⊆
  the question's read level and ⊆ the form's respond level).
- **Profile-backed questions** also follow the person field. A viewer sees
  the question, and its stored answer in every submission, only if they can
  read both the question and the person field. In `update_profile` mode they
  can change it only if they can write both. In `prefill` mode, writing the
  question is enough, because the profile isn't changed. Storing the answer
  on the form therefore never widens who can see the profile data.

A viewer who can read but not write a question sees it read-only, with the
person-fields access message ("Only leaders can change this").

### 5.3 Evaluator

`FormAccess.new(viewer, subject, form)`, a subclass of `AudienceAccess`:

```ruby
can_respond?               # respond level component or a respond badge grant
can_read?                  # read level component or any badge grant
question_readable?(q)      # q's effective read level, and the person field's (if any)
question_writable?(q)      # q's effective write level, and the person field's in update_profile mode
can_sign?(q)               # §7.1
```

List form: `Form#readable_subjects_for(viewer)` and
`#respondable_subjects_for(viewer)` return a `Person` relation (level
relations `.or` badge-grant coverage, intersected with the audience). A
consistency test asserts the list form matches `FormAccess` for every
subject in the fixture world, as for person fields.

### 5.4 Who manages forms

| Action | Who |
|---|---|
| Create a form | Admins, and managers of the form's team (or an ancestor) |
| Edit, publish, open, close, duplicate, archive | Same |
| Set a completion badge or badge grants | Admins only (both widen access or status) |
| Add a profile-backed question | Anyone who may edit the form. It grants nothing: each viewer still needs the person field's own levels (§5.2) |
| Delete a form | Admins, and only with no submitted submissions; otherwise archive |

---

## 6. Responding

### 6.1 "Forms to complete"

A person sees every open form where they can respond for at least one subject
in its audience whose response is not complete, or needs their signature:
themselves, and each ward (one entry per child). Leaders get no extra
entries (they work from the results page). Shown:

- On the dashboard, as a card ("3 forms to complete · Meal Choices for Avery,
  due Oct 12 · Consent for Jordan: needs your signature").
- At `/forms` ("My forms"): To do, Submitted, Closed.
- In the weekly digest (§11.2).

### 6.2 The fill page

`/forms/:id/responses/:subject_id/edit`. The subject is explicit in the URL
and the header ("Meal Choices for **Avery Ash**, filled in by you as her
guardian"), so a parent with two children can't confuse them.

- Questions the viewer can't read are omitted; read-only ones show values.
- **Save** keeps the draft. **Submit** validates and moves it on (§4).
- On an update, each changed answer is marked against the active version
  ("was: Slim 4"), and a profile-backed question whose profile value changed
  since the last signing says so (§8.2).
- A required question the respondent can't write (a leader-only question,
  or a profile field only leaders can write) doesn't block Submit. The
  response shows "Waiting for: …" until someone who can supply it does.

### 6.3 Paper forms and late entries

Leaders with respond access use the same page for any subject. After close,
`late_entry: leaders` lets them still submit; the submission is marked
`entered_late`. Leaders can't sign as a guardian (§7.1); they record a paper
signature only where the question's `signer` allows `leader`.

### 6.4 Writing to the profile

"Updates profile" answers are written **when the submission activates**, not
when it is saved or submitted. An unsigned update never changes the profile.

The write is `subject.assign_field_values(values, acting: submitted_by)`, so
the person field's write rule is checked against the person who submitted
it, as of activation. If that person can no longer write a field (for
example, guardianship ended in between), the key is recorded in
`profile_skipped`, the profile is left alone, and the response shows "Not
copied to profile: Dietary Restrictions". The `person_fields - value changed`
hook fires for each field written, as for any other profile edit.

---

## 7. Signatures and versions

### 7.1 Who signs

| `signer` | Who may sign |
|---|---|
| `subject` | the subject |
| `guardian` | an active guardian of the subject |
| `guardian_if_minor` | an active guardian if the subject has one (`subject.guardians.exists?`), otherwise the subject. Guardianship already ends at the configured age (`Relationship.guardianship_age_limit`), so an 18-year-old signs for themselves with no extra rule |
| `leader` | a leader with respond access, recording a paper signature (`signer_role: leader`, shown as "Paper form recorded by …") |

One signature per signature question per submission; the first valid one
satisfies it.

### 7.2 Capturing intent

A signature question shows its text, the answers being signed (a read-only
summary of the submission), the signer's name, and "Type your full name to
sign: ______ [Sign]". The typed name must match the signer's display or
legal name (case and whitespace insensitive). On sign we store `signed_at`,
`ip_address`, `user_agent`, and the content digest. No drawn signatures in
v1.

### 7.3 Signatures cover content, and never carry over

The digest covers the form's text at the submission's `form_version` and the
submission's answers. So:

- **Every new submission needs new signatures.** Updating a consent form
  means signing again, even if only one answer changed.
- **Editing a pending submission revokes its signatures** (§4, step 6).
- "What exactly did this parent sign on Oct 3?" is answered by opening
  submission #1: its answers, the form text at its version (from
  `form_questions`' paper trail), and the signature row.

### 7.4 Form versions

Changing an **open** form's statement, acknowledgment, or signature text,
adding a required question, or changing a choice list goes through
**Publish changes**, which bumps `forms.version` and asks how to treat
existing active submissions:

- **Keep**: they stay complete (typo fixes).
- **Require re-confirmation**: responses whose active submission is on an
  older version become `needs_reconfirmation` and lose the completion badge.
  Their active submission **stays active**: its answers are still the latest
  signed data, so reports keep showing them, marked "Signed on version 1".
  Respondents see "This form changed. Please review and sign again," and the
  update draft starts from the active answers, with new questions blank.

Drafts and pending submissions on an older version are moved to the new
version; pending ones go back to draft with signatures revoked.

---

## 8. Status, profile changes, and badges

### 8.1 Response status

| Status | Meaning |
|---|---|
| Not started | In the audience, no response row |
| Draft | A draft, nothing active |
| Waiting | Submitted, nothing active yet: waiting for a signature or for an answer someone else must give |
| Complete | Has an active submission on an accepted form version, with no unresolved required profile change |
| Needs re-confirmation | Has an active submission, but the form changed (§7.4) or profile data it set changed (§8.2) |
| Withdrawn | Active submission withdrawn, nothing newer |

Plus the `update_in_progress` flag, shown as "Complete · update in
progress". `FormResponse#sync_status!` recomputes both and is the one place
that grants or removes the badge.

### 8.2 Profile changed since signing

For every "updates profile" question, the active submission's answer is what
was signed and the profile holds the current value. When they differ:

- The response, the results grid, and the profile-backed column of reports
  show **"Changed since signed on Oct 3"** with both values.
- If the form has `reconfirm_on_profile_change`, the response becomes
  `needs_reconfirmation` (badge off) until a new submission is signed.
  Otherwise it's a flag only.

Detected on `person_fields - value changed` (an internal subscriber, not a
user Hook): re-sync responses whose active submission has an
`update_profile` question on that field. Note that this fires for changes
from anywhere, including another form that updates the same field. That is
correct: the first form's signed value is no longer current. "Filled in from
profile" questions never flag, since they were never meant to match.

No field is locked. Profile data stays editable through its normal rules; a
form that cares says so through this flag.

### 8.3 Completion badge

While a response is `complete`, the subject holds the form's completion
badge; otherwise the badge is removed. `badge_assignments - create/destroy`
hooks fire as usual. "2027 Parent Consent Signed" works like "2027 FIRST
Consent Signed", so the Eligibility Report and other badge-based reports need
no change.

---

## 9. Reports

**Reports read active submissions, alongside current profile data.** Drafts,
pending updates, and superseded versions don't appear in results unless
asked for. Every view shows only subjects in `readable_subjects_for(viewer)`
and only cells the viewer can read (§5.2); tallies count only those cells.

### 9.1 Status

`/forms/:id`: counts and lists per status (§8.1), filterable by sub-team, with
bulk **Remind** (§11.1) and **Export CSV**.

### 9.2 Results grid

One row per person in the audience:

- **Active answers**: one column per question (headings and statements
  omitted).
- **Profile columns**: any person fields the viewer can read, chosen per
  view (Dietary Restrictions, Shirt Size, Phone), showing **current** profile
  values. For an "updates profile" question, the cell shows the signed
  answer, marked if the profile has changed since.
- **Record columns**: status, version number, signed by, signed on, form
  version, "update in progress".

A **Show** toggle switches between *Active (signed)*, the default, and
*Latest*, which shows draft or pending updates instead where they exist,
marked as unsigned. Saved column choices persist per viewer and form. Print
uses the shared report print CSS. CSV export applies the same per-cell rules.

### 9.3 Tally

For every `select`, `multi_select`, `boolean`, and `intent` question: a count
per choice, plus "no answer", over active submissions in a chosen
population:

- the form's audience (default), or a sub-team, or
- an event's people: those who answered intent **yes** (expected) or those
  **checked in** (actual) (§10).

### 9.4 Order sheet

Pick an event and one or more questions (e.g. "Jimmy John's", "Please
Remove"), plus profile fields to show alongside (Dietary Restrictions). The
sheet lists each person with their active choices and profile data, then the
tally. It can be based on **expected** (intent yes, for ordering ahead) or
**checked in** (for handing out), and prints as bag labels or a list. People
with no active meal submission are listed separately ("No choice on file:
3"), so no one is silently left out.

The order sheet can use the event's attached forms (§10) or any open season
form the viewer can read; the meal form doesn't have to be attached to every
event.

### 9.5 Custom reports (Pages)

HBR's reports are dynamic Pages (ERB, admin-authored). Forms provides a
read API that applies the viewing person's permissions, because a Page's
code runs for whoever views it:

```ruby
report = FormReport.new(Form.find_by!(key: "parent_consent_2027"), viewer: current_person)
report.rows              # one per readable subject: person, status, active submission
report.answer(row, "photo_release")             # nil if the viewer can't read it
report.profile(row, "dietary_restrictions")     # current profile value, same rule
report.changed_since_signed?(row, "dietary_restrictions")
```

Pages should use `FormReport`, never `FormSubmission` directly. The Pages
editor shows that note when the feature is on.

### 9.6 On the profile

A **Forms on file** section on `people/show` lists forms with an active
submission the viewer can read: form, status, signed on and by, and a link
to the response. Phase 2 (it edits an upstream view; see §14.2).

---

## 10. Events

### 10.1 Event forms

A form with `event_id` is an **event form** (a trip permission slip, a
"coming Saturday?" poll). Its audience defaults to the event's team, its
`closes_at` to the event start, and the event page shows a Forms panel: each
attached form with its status counts and a link to its results.

### 10.2 Intent is not attendance

**An intent answer is a planning count only. A person counts as attending
only when checked in.**

- An `intent` question never creates, changes, or deletes a `Checkin`, and
  never affects time-clock hours, travel eligibility, or the Attendance and
  Eligibility reports, which keep reading check-ins only.
- The event panel labels the numbers as intent: "Expected: 18 yes, 4 maybe,
  6 no, 12 no answer". After check-ins begin it adds "Checked in: 21" and,
  for leaders, two lists: said yes but not checked in; checked in without
  saying yes.
- Intent appears on the event page and the form's results, never in a
  person's attendance history.

### 10.3 Season forms used at events

The meal form is a season form, not an event form. Events reach it through
the order sheet (§9.4). Nothing about a season form changes when an event
uses it.

---

## 11. Notifications and scheduling

### 11.1 Reminders

**Remind** on the status page sends to every not-complete subject in the
current filter (including Needs re-confirmation and Waiting). Recipients are
the people who can act: the subject (if they have an account and can
respond) and their guardians (if the respond level includes `guardian`, or a
guardian signature is outstanding). One email per recipient per form, listing
each of their subjects: "Meal Choices is due Oct 12 for Avery and Jordan."
Sent with `SendEmailJob`; logged in `form_reminders`.

Automatic reminders (N days before close) are Phase 4.

### 11.2 Digest

The weekly digest (`Infodump`) gains a "Forms to complete" section. This
edits an upstream file; propose a digest-section seam first (§14.2).

### 11.3 Opening and closing

A recurring Solid Queue job every 5 minutes opens `draft` forms past
`opens_at` and closes `open` forms past `closes_at`. Manual Open and Close
buttons do the same immediately. Closing doesn't change any submission:
pending ones can still be signed (a signature is not a late entry), but new
drafts and updates need `late_entry`.

---

## 12. UX

### 12.1 Navigation and registration

```ruby
GatherPack::Features.register_built_in(
  GatherPack::Feature.new(
    key: :forms,
    label: "Forms",
    description: "Collect information, consent, and event plans from members and their families",
    default_enabled: false,
    nav_section: "People",
    nav_position: 40,
    nav_items: [ GatherPack::Feature::NavItem.new(label: "Forms", path: :forms_path, icon: "file-signature") ]
  )
)
```

`/forms` is "My forms" for everyone, plus "Manage" (forms the viewer can
edit) for leaders and admins.

### 12.2 Form builder

- Settings: title, key, description, team, audience badge, event, kind,
  respond and read levels (the same selects and audience explanations as the
  person field form), badge grants, dates, allow updates, late entry,
  re-confirm on profile change, completion badge.
- Questions: an ordered list with Move up / Move down, add by kind,
  "Profile" setting for inputs (*Form only* / *Filled in from profile* /
  *Updates profile* + field), per-question levels under "Advanced".
- **Preview as…** (the person-fields component): pick a viewer and subject,
  see what that viewer sees and can change.
- **Publish changes** on an open form with responses (§7.4).
- **Duplicate**: copies settings and questions, not responses. "2027-28 Meal
  Choices" is a duplicate with new dates and key.

### 12.3 Routes

```ruby
resources :forms do
  member { post :open; post :close; post :publish; post :duplicate; post :remind; get :results; get :tally; get :order_sheet }
  resources :questions, controller: "form_questions", except: [ :index, :show ] do
    member { post :move }
  end
  resources :responses, controller: "form_responses", param: :subject_id, only: [ :show, :edit, :update ] do
    member { post :submit; post :start_update; post :discard; post :withdraw; post :sign }
    resources :submissions, controller: "form_submissions", only: [ :show ]
  end
  resources :badge_grants, controller: "form_badge_grants", only: [ :create, :update, :destroy ]
end
```

---

## 13. Auditing, Hooks, and data handling

- Every new model gets `has_paper_trail versions: { class_name: "AuditLog" }`.
  `form_questions`' trail is also how earlier form text is rendered (§7.3).
- `answers` and signature params go in `filter_parameters`.
- `FormSubmission.ransackable_attributes` exposes `status`, `submitted_at`,
  never `answers`. Tallies are computed in SQL after the readable-subject
  filter, not through Ransack.

### 13.1 Hooks

#### Record events (`include CanBeHooked`, add to `Hook.catalog`)

| Table | Why |
|---|---|
| `forms` | Definition and status changes (post "Permission slips are open" to Slack) |
| `form_responses` | The per-person summary; `update` fires on status changes |
| `form_submissions` | Core data, as `checkin_field_responses` and `person_field_values` |
| `form_signatures` | Consent is what integrations care about most; create and revoke (update) |
| `form_badge_grants` | Changes who can see responses, as `person_field_badge_grants` |

**Not hooked:** `form_questions` (structure; Publish shows up as
`forms - update`) and `form_reminders` (a log).

#### Domain events

| Event | `model` | Fired when |
|---|---|---|
| `form_submissions - submitted` | `FormSubmission` | Submit. Record `update` fires on every save, so hook code would otherwise diff `status` |
| `form_submissions - activated` | `FormSubmission` | It becomes the active version (after profile writes). `model.based_on` is the version it replaced |
| `form_responses - completed` | `FormResponse` | The response becomes complete, e.g. the parent's signature arrives days after the student submitted |
| `form_responses - incomplete` | `FormResponse` | A complete response stops being complete: withdrawn, form re-confirmation, or a profile change on a `reconfirm_on_profile_change` form. `model.status` says which |

Fired after commit from the transition methods, as
`person_fields - value changed` is.

#### Considered and deferred

- **`forms - opened` / `forms - closed`.** The record `update` hook already
  fires when the job changes `status`.
- **`form_responses - overdue`.** Needs a daily job at the deadline; add with
  automatic reminders if wanted.

#### Data handling note

Hooks receive unfiltered answers, including restricted questions and
profile-backed values. The Hook form's notice for person-field events is
extended to these events.

---

## 14. Fit with the fork strategy

### 14.1 Branch

`feature/forms`, branched from `feature/person-fields` (declared
dependency). Upstream naming, no `Hbr` namespace: a general capability
intended for upstream after person fields. Upstream issue first, framed
generally: "Forms: collect information and consent from members and
guardians." Flag `feature_forms`, off by default.

### 14.2 Upstream files touched (kept small)

Almost everything is new files. Expected edits to existing upstream files:

| File | Why | Seam to propose instead |
|---|---|---|
| `config/routes.rb` | Routes | The feature's `routes_proc` may avoid this; confirm |
| `config/initializers/features.rb` | Registration | (already touched by person-fields) |
| `app/models/hook.rb` | Catalog entries | A catalog registration API |
| `app/views/welcome/dashboard.html.erb`, `app/controllers/welcome_controller.rb` | Forms to complete card | **Dashboard card registry** on `GatherPack::Feature` |
| `app/views/events/show.html.erb` | Event forms panel | **Event panel slot** |
| `app/views/people/show.html.erb` | Forms on file (§9.6) | **Profile section slot** (already touched by person-fields) |
| `app/models/infodump.rb` | Digest section | **Digest section registry** |
| `app/views/pages/_form.html.erb` | `FormReport` note (§9.5) | Optional; can be documentation instead |
| `config/initializers/filter_parameter_logging.rb` | Answers | (already touched) |
| `config/recurring.yml` | Open/close job | |

The registries are small, generic, and useful to any plugin, so they are
good seam PRs to offer upstream before Forms.

### 14.3 Migrations

Seven `create_table` migrations, reversible, primary DB only (run
`db:migrate:primary` and `db:migrate:versions` per AGENTS.md).

---

## 15. Rollout

| Phase | Scope | Replaces |
|---|---|---|
| **0: Extract** (done) | `AudienceLevels`, `AudienceAccess`, and `FieldValueType` on `feature/person-fields` (§2.1) | |
| **1: Core** | forms, questions (input in all three profile modes, heading, statement), responses, submissions with history, update and discard; `FormAccess` and the list form with the consistency test; profile writes on activation; builder, Preview as…, Duplicate; fill page; My forms; dashboard card; status page, results grid with profile columns, CSV, tally; `FormReport`; manual Remind; open/close job; hooks for these tables | The meal spreadsheet, apart from the order sheet |
| **2: Consent** | acknowledgment and signature questions, `form_signatures`, form versions and Publish, `reconfirm_on_profile_change`, completion badge, `form_badge_grants`, Forms on file, the completed/incomplete hooks | Paper consent forms |
| **3: Events** | `event_id`, the intent question, event panel, expected vs checked in, order sheet | The Attending column and the hand-built order |
| **4: Later** | automatic reminders, digest section, file-upload questions (insurance cards; needs a privacy decision on Active Storage access), conditional questions, payment link | |

### 15.1 Open questions

1. **Leaders on "Forms to complete".** v1 leaves leaders off unless they are
   the subject or a guardian. Should a "Leader to-do" card show forms with
   leader-only questions or paper signatures waiting?
2. **Who can see tallies.** v1 shows tallies only to people who can read the
   underlying answers. Should a form be able to publish aggregate counts more
   widely ("12 pizza, 4 sub") without individual answers?
3. **One guardian or all?** v1 accepts the first guardian's signature. Should
   a signature question be able to require every active guardian?
4. **Conditional questions.** The meal form doesn't need them; trip forms
   might ("needs medication at camp? → which"). One-level "show if question X
   is Y" would cover most cases.

---

## Appendix A: Worked examples

### A.1 2026-27 Meal Choices (season form)

- Key `meal_choices_2027`. Team: Students. Kind: general. Respond: `family`.
  Read: `family`, plus a read grant for a "Meal Coordinator" badge. Closes
  Oct 12. Allow updates: yes.
- Questions:
  - heading "5 Guys"; select "5 Guys" (Cheeseburger, Grilled Cheese, Hot
    Dog, …)
  - heading "Jimmy John's"; select "Sandwich" (Slim 1–6, Big John, Totally
    Tuna, Turkey Tom, Vito, The Pepe, …); select "JJ Dessert" (Chocolate
    Chip, …)
  - select "Pizza" (Cheese, Pepperoni, Sausage); select "Subway" (Turkey,
    Ham, Tuna); multi_select "Please remove" (Lettuce, Tomatoes, Cheese)
  - select "Cookie", select "Chip", select "Entrée 1", select "Entrée 2"
  - multi_select or text "Wishlist"
  - Dietary Restrictions, **updates profile** (the system person field; one
    place for allergies)
- No signatures, so each submission activates on submit. A student who
  changes their sandwich in January submits an update; it replaces the
  active version at once, and the old one stays in the history.
- The "Attending" column becomes an event form per event, or the order
  sheet run against checked-in people.
- Importing this season's spreadsheet is a one-off script (outside the
  feature) that maps the inconsistent spellings to the choice lists and
  creates submission #1 per person with `submitted_by` = the importer.

### A.2 2027 Parent Consent (consent form)

- Key `parent_consent_2027`. Team: root team, audience badge "Student".
  Kind: consent. Respond and read: `family`. Completion badge "2027 Parent
  Consent Signed". Re-confirm on profile change: yes.
- Questions: statement (the release text); Emergency Contact (a custom
  person field) and Phone, **updates profile**; Dietary Restrictions,
  **updates profile**; acknowledgment "I have read the code of conduct"
  (write override `self`, so the student ticks it); signature
  (`guardian_if_minor`).
- October: the student ticks the acknowledgment and submits; submission #1
  is pending ("Waiting: parent signature"). The parent reviews and signs;
  #1 activates, the profile is updated, the badge is granted,
  `form_responses - completed` fires.
- December: a leader records a new allergy on the profile. The consent
  response shows "Dietary Restrictions changed since signed on Oct 3" and,
  because of the form setting, becomes Needs re-confirmation; the badge
  comes off. The parent clicks Update: draft #2 starts with the current
  profile values and the October answers, and needs a new signature. Until
  the parent signs, reports still show #1's answers, marked "needs
  re-confirmation".
- The Eligibility Report reads the badge; a custom Page lists every
  student's photo release answer and current allergies via `FormReport`.

### A.3 Saturday Build (event intent)

- Event form on the Saturday event, closes at the event start. Respond:
  `self_and_leaders`. Questions: intent "Are you coming?".
- Friday: the event panel shows "Expected: 18 yes, 4 maybe". The order sheet
  (expected) from `meal_choices_2027` gives the Jimmy John's order.
  Saturday: 21 check in; the panel lists the 3 who came without saying yes.
  Attendance and hours come from the 21 check-ins only.
