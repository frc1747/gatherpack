# Spec: Membership Intake (joining and rejoining a team)

Status: draft rev. 2, 2026-11-06. Nothing is built. Code facts were checked at integration `49609326`. Decisions in §13 are defaults the product owner can overturn; there are no open questions.

Rev. 2 (also adds an optional form expiry, §7.5): no seasons. The product owner's rule is that time is a date or a date range on a record or a check, never a model. Removed: `Season`, `feature/seasons`, `season_enrollments`, `renews_each_season`, the rollover job, "ways to join" and renewal as its own flow. A registration is now a link with dates, the teams people may apply to, and a checklist. "Signed recently enough" is decided by the item that uses the form (§7).

This spec lives on `hbr/platform`, not on a feature branch. The generic branches are meant for upstream, so they must not mention HBR. HBR's setup is Appendix A and nowhere else.

The companion spec `checklists-spec.md` designs checklists (one feature, which also absorbs Commitments); §10 states what intake needs from it and where it is provided (checklists §13).

## 1. Purpose

A person can join a team, or come back to it, from inside GatherPack with nobody hand-creating records. Two ways in share one flow:

- **Kiosk.** A manager is signed in at a callout. People in the room give a few facts and finish at home.
- **Self-service.** A public link that an organizer opens and closes by date.

What this prevents, all seen in the last registration: guardians not linked, people with no login, students missing the team that decides who is new, duplicate placeholders, a typo'd email, a student listed twice.

### 1.1 The rule for this spec

Build from what GatherPack has: people, users, relationships, teams, memberships, badges, forms, `MembershipApplication`, checklists. A new case is configuration (a registration, a checklist, a date) or an additive check. If a case needs a new model for time, stop and revise this spec with a rev. note saying why.

GatherPack code has no words like student, parent or rookie. Those are names an organization gives to teams, badges and forms.

### 1.2 Use cases

| Use case | Verdict | How |
|---|---|---|
| A guardian registers one or more children, and themselves | Fits | Household entry (§4.1) |
| A young person registers and names a guardian | Fits | Guardian confirms by email (§4.2) |
| An adult joins as a mentor or volunteer | Fits | A registration (or the same one) whose teams and checklist suit adults |
| Returning members rejoin, pre-filled, re-confirming info and re-signing | Fits | Same link and checklist; items older than the item's date are due again (§7.2) |
| A sibling or returning family is matched, not duplicated | Fits | Login email, then manager review (§4.3) |
| Registering in the room on a shared device | Fits | Kiosk mode (§3) |
| FIRST registration and consent, tracked not automated | Fits | A badge item on the checklist (§7.3) |
| Dues, background checks, training | Fits | A badge item, or a count item (dues in units) |
| Joining a team that needs no approval | Fits | The registration adds the membership on verification (§8.4) |
| Applicant chooses among several teams | Fits | A registration lists teams, "any of"; each pick makes its own application (§2) |
| Several organizations or teams in one install | Fits | A registration belongs to a team; its managers run it |
| Alumni, sponsors, supporters | Fits | A registration for their team with a short checklist |
| Mid-year joiners | Fits | The registration stays open; nothing assumes a start date |
| A student reaching the guardianship age | Fits | Guardian rules go by age when checked (§5.4) |
| Capacity limit and waiting list | Additive, later | A cap on a registration; extra entries are held and promoted by hand (§8.5) |
| Moving between teams | Non-goal | Existing memberships screens |
| Filing on FIRST's own site | Non-goal | It can't be automated; intake links and tracks |
| Collecting dues online | Non-goal | A checklist item can count dues credited elsewhere; a ledger-balance item is a later checklist kind |
| Registering with no email | Non-goal | Verification needs an email (§5.1). The staff path covers it. |
| Merging people already duplicated | Additive, later | `feature/person-merge` (§4.4) |

## 2. Concepts

| Concept | Meaning |
|---|---|
| Registration | A link with `opens_at` and `closes_at`, a kiosk switch, a self-service switch, the teams people may apply to, a checklist, and placement lists (§6). Belongs to a team; that team's managers run it. |
| Entry | One in-progress sign-up by one household. Holds a few facts and a verification token before any person record exists (§5.2). Expires. |
| Household | The people on one entry: the one who verified, and anyone they add. |
| Applicant | A person with a pending `MembershipApplication` from a registration. Computed, never stored as a status. |
| Checklist | A checklist (`checklists-spec.md`) the registration points to. Intake shows its status and never defines its checks. |

- **Teams people may apply to** is a list meaning any of: "People can apply to any of these teams. They pick the ones they want." Each pick is one application, one decision.
- Time lives in dates on the registration (open, close, entry retention) and on the items of the checklist (§7). There is no year or season anywhere in the model.
- **Copy registration** copies the team list, checklist reference and placement lists, and proposes dates shifted by the gap between the old open and close dates, for a person to confirm. Every date is configuration. The old link, once closed, says "Registration has closed." and shows the successor's open date if one is set.
- A single registration offering two genuinely different flows (adults and children asked different questions) is two registrations on one team. Different questions are different checklists. No "ways to join" construct.

## 3. Two modes, one flow

Both modes run the same flow: pick a team, give the facts, name the household, create an entry, verify, finish at home.

| | Kiosk | Self-service |
|---|---|---|
| Address | `/join/<slug>/kiosk` | `/join/<slug>` |
| Who opens it | A signed-in admin, or a manager of the registration's team who is on the kiosk accounts team | Anyone with the link while the registration is open |
| Why less restricted | A manager is in the room | Nothing; every step is defended (§9) |
| Records created | Person, login and application right away, marked not yet verified | Only an entry until the email is verified |
| What it asks | Name, grade or birth year, own email (twice), guardian email when needed | Name, email, team; the rest after verification |
| Never shown | Existing records, matches, medical or private fields, forms, signatures, birthdays, phones | Matches, whether an email has an account, anyone else's data |
| Signing | Never | After verification, in the person's own session |
| Reset | After each submission and 60 seconds idle | n/a |
| Rate limit | 30 entries a minute per device account | §9.2 |
| Bot check | None (signed-in device) | §9.3 |
| After submit | "Thanks, <first name>. Check your email to finish." | The same words |
| Staff view | "Waiting to finish" list | Entries screen |

Screens are one short question each, in order, with plain copy: who is joining (the teams, with "Choose any that apply"), name, email, the registration's first-step questions (a person field or two), guardian name and email only when a guardian is needed (§5.4), "Anyone else joining with them?" (repeat), done. Self-service may defer the household until after verification.

### 3.1 Kiosk access

A signed-in device like the time kiosk. It reuses the time kiosk gate (`time_kiosk_controller.rb:124-129`, setting `time_kiosk_users_team`, `lib/settings.rb:146`) and also requires managing the registration's team or an ancestor. A setting `intake_kiosk_users_team` overrides the team (blank means the time kiosk's). The layout is a copy of `layouts/kiosk.html.erb` with no navigation, search or links out and no signed-in name or photo. A signed-out device is sent to sign in and back.

## 4. Families, matching and merging

### 4.1 Household

A household entry holds one verified adult and anyone they add. Guardian relationships are created from the household's shape, never typed by staff: the adult adds a child, and the registration's relationship type (with `guardianship` set, `relationship.rb:15-33`) links them. A child who registers on their own and names a guardian is linked when the guardian confirms.

### 4.2 A young person naming a guardian

The entry holds the guardian's name and email. The guardian gets "<Name> would like to join <team>. Confirm you are their guardian." Opening the link verifies the guardian's email, finds or creates their login (§4.3) and creates the relationship. Until then the application shows "Waiting for a guardian". A manager can correct the guardian email or link an existing person. A confirmation is a statement, not proof; the approval screen shows "Guardian confirmed by email on <date>". A minor can't create a guardian tie the guardian did not confirm.

### 4.3 Matching, not duplicating

Server side, at verification, never shown to the applicant:

1. **Login email** matches `users.email` (trimmed, case-insensitive): the entry attaches to that person. No new `User` or `Person`.
2. **Name (and birthday where recorded) among people with no login:** held as "Might be the same person as <name>. Link or keep separate." Default: keep separate.
3. **Guardian by email**: matched like (1); an existing guardian is linked, not created.
4. **Within the household**: the same name or the same email twice is refused on that screen.

The kiosk applies the same rules and shows possible matches only to the manager, in "Waiting to finish".

### 4.4 Merging

Intake prevents duplicates; it doesn't merge them. Merging means moving memberships, relationships, badges, tokens, responses, sign-ups, punches and check-ins with one audit trail, which is `feature/person-merge`, later.

## 5. Accounts

### 5.1 Verification

No `Person` or `User` comes from a public request until its email is verified. The link is single use, expires in 48 hours (a setting, §13.1), and is stored as a digest. Opening it for a new email creates the records and asks for a password. For an email with a login it says "Sign in to continue" with a normal sign-in link and never signs anyone in; intake adds no login path.

### 5.2 Where the email lives

On the `User` (`person.rb:24`; `users.email`, `db/schema.rb:1164`). Before verification it lives on the entry, encrypted. On the kiosk the `User` is created at once with a random password, `intake_login_verified_at` null; the invitation link verifies and sets a password. Forgot password also verifies.

### 5.3 Typo defence

The kiosk takes the email twice and blocks a mismatch. Both modes hint at common slips ("Did you mean gmail.com?", list in a setting). After verification the person sees their email with "Change email", which re-verifies. An invitation unopened after 3 days shows in "Waiting to finish" with its age, so a typo is caught while the person is reachable.

### 5.4 Minors and the guardianship age limit

"Needs a guardian" uses the birthday and `Relationship.guardianship_age_limit` (`relationship.rb:30`), 18 when unset, as forms do (`form_access.rb:116-120`). No birthday on file means a guardian is needed (`form_access.rb:104`). For such a person:

- Their own login is created, but intake sends nothing to their address until a guardian is linked, except that they started.
- A person of age may register alone; a form can still ask a guardian to sign (`guardian_if_minor`).
- A person who passes the limit later needs nothing from intake: rules go by age when checked (`active_guardianships`).

Guardian wording and counts appear only when a guardian is reached. A young person sees "Your guardian will be asked to sign these." A person of age sees nothing about guardians.

### 5.5 Every email gets a login

Any person with a verified email has a `User`. Intake never creates a `User` from a name alone.

## 6. Placement

On approval, intake can add the person to more than the team applied for. The registration has two plain lists:

- **Also add to these teams.** Always added, idempotent.
- **Also give these badges.** Always given. Badges record facts ("Applied through the 2027 callout"), not status.
- **Also add a guardian to these teams** (only when a guardian is involved): the guardian joins the listed teams.

That is all the machinery. The two cases that used to need rules:

- **Class team from graduation year.** Least machinery: the approval screen prompts the manager with a team picker for the registration's optional "Also pick one of these teams" list (any one, the manager chooses), preselected when the person has a field value that matches a team's name. The preselection is a suggestion in the view, not logic that decides. Without the preselection it is a manager step, which is the minimum. Anyone wanting automatic placement uses one registration per class team.
- **New or returning.** Intake computes nothing. "New" is a question the checklist or a report answers from memberships and badges (checklists), and a manager grants the badge when approving if the organization wants it. An organization that wants an automatic "first-time" badge adds "Also give these badges" on a registration for newcomers, and uses a separate registration for people who already hold a membership.

Approval stays `MembershipApplication#approve!`. A concern included from an initializer runs the lists after `approve!` saves (`membership_application.rb:22`), in the same transaction when possible. The approval screen shows "Will also join: ... Will get: ..." before the button. If the optional pick is required and unchosen, Approve says "Choose a team" by the picker. Upstream's file is not edited.

## 7. The checklist and coming back

### 7.1 The checklist

The registration points to a checklist (`checklist_id`). For each person (and each ward, §7.4) the page shows the checklist's items as Done / Almost / Not yet / Not counted (the default words; statuses `met`, `pending`, `not_met`, `exempt`) with a "fix" link. Intake defines no checks.

Usual items: a form complete (with a date, §7.2), a guardian signature, "confirm your information", has a login, a badge item (FIRST registered, FIRST consent, background check), a count item (dues in units), another checklist. Outside GatherPack: FIRST is synced into badges by a script (Appendix A) and the item's fix link goes to a page the organization writes; dues are a count item or a badge; background checks and training are badges granted by whoever verifies. Intake collects no payments and runs no checks.

### 7.2 Dates decide what is recent enough

A form keeps every response and every signed version; a person's answers and signatures are never expired or archived by intake. Whether a response counts is decided by the item using it: `form_complete` with "completed on or after <date>". The date is configuration on the item. The same form can serve a team that wants this year's signature and another that accepts last year's.

Checked in the forms code whether a person can sign again a response that's already complete:

- Yes, when the form's `allow_updates` is on (default true, `db/schema.rb:421`). `FormAccess#can_update?` lets a person start a new version after an earlier one (`form_access.rb:79-82`). The response page offers "Update answers" on a complete response (`form_responses/show.html.erb:100`). `edit` builds a new draft from the active submission (`form_responses_controller.rb:12-18`; `form_response.rb:37-42`).
- The new version needs its own signatures: signatures belong to a submission (`form_submission.rb:66-72`). Activating it stamps `activated_at` (`form_submission.rb:173-177`, column `db/schema.rb:394`), which is the timestamp the date check reads.
- The old version stays active, and the response stays complete, until the new one is activated, so a returning member is never shown as having nothing signed while they work through it.
- When `allow_updates` is off, `can_update?` blocks a complete response unless it needs re-confirmation. A form used for coming back needs `allow_updates` on, which is the default. For one that has it off, the only forms change is a small additive "Sign again" action that the checklist item's fix link uses and `can_update?` permits when a checklist item asks for it. Phase 1 needs no forms change. An expired response (§7.5) can always be updated, so expiry doesn't need it either.

Expiry is the form's own rule and sits beside this window; see §7.5 for when to use which.

The completion badge, if the form has one, stays as it is today: given when complete, removed only when the response stops being complete. A due-again item does not remove it, because a new version doesn't make the response incomplete.

"Confirm your information" is likewise a form: "updates profile" questions, which start from the current profile (`form_response.rb:51`), and a final "These are correct" confirmation. The checklist item is `form_complete` with a date.

### 7.3 Coming back is the same checklist

There is no renewal flow or status. A returning member opens the same link (or their own checklist from the dashboard card), signs in, and sees the registration's items. Items whose responses are older than the item's date show as Not yet, with their answers pre-filled, as they are for anyone updating a form. Items whose responses are recent enough show Done. A person already on the team doesn't make an application (`membership_application_policy.rb:23` refuses it); the registration shows them the checklist only. Whether to ask members to come back is the organization's choice: it sets a date on the item.

"Who hasn't come back" is a filter on the checklist's report page (people covered whose overall isn't Done; checklists §10.4), not a status. Intake never removes anyone. Managers act on the list with the existing membership screens.

### 7.4 Who acts

A person acts on their own items. A guardian acts on a ward's items the way sign-ups handle on behalf of: the checklist page offers a household switcher, and a guardian signs the forms the form allows (`form_access.rb:104`), seeing only what the ward's checklist shows. Guardian wording only appears when a guardian is reached (§5.4).

### 7.5 Form expiry (the form's own rule)

An optional expiry on a form, as a date, not a season. One choice on the form's details, "Responses expire": **Never** (default), **On <date>**, or **<N> months after signing**. Two nullable columns, `forms.expires_on` (date) and `forms.valid_for_months` (integer), with a validation that at most one is set. Recommendation: offer both. A fixed date serves "this agreement is void after <date>"; the rolling period serves a yearly physical, where each person's clock starts when they sign. Neither needs the other, and together they are two columns and one method.

A response's expiry is `expires_on`, or its active submission's `activated_at` (`db/schema.rb:394`) plus `valid_for_months`. Expiry has effect from the start of that day or moment; "expire on 1 June" means a response no longer counts on 1 June.

**What happens, using the states forms already has.** `FormResponse#reconfirmation_reason` (`form_response.rb:69-73`) returns `:form` or `:profile` for a response with an active submission, and `computed_status` turns any reason into `needs_reconfirmation` (`:100-103`). Expiry adds a third reason, `:expired`, and nothing else in the status logic changes:

- The response shows **Needs re-confirmation**, and the form is a to-do again wherever forms already treat `needs_reconfirmation` as owed (it is a report status, `form_report.rb:23`; the dashboard card and reminders should be confirmed in the build).
- A person can always update it: `FormAccess#can_update?` allows a response in `needs_reconfirmation` even when the form's `allow_updates` is off (`form_access.rb:79-82,152-153`). So an expired response needs no "Sign again" action.
- History is kept. Nothing is deleted or rewritten; the old submission stays active, with its answers pre-filled as the starting point (`form_response.rb:48-57`), until a new one replaces it. A new submission gets its own signatures (`form_submission.rb:66-72`), and its `activated_at` restarts a rolling clock.
- Completion badge: removed while the response is not complete (`form_response.rb:117-127`), as it is for any re-confirmation. That is right for expiry: a badge that outlived the physical would record something false.
- Hooks: the existing `form_responses - incomplete` fires when the status changes (`form_response.rb:96-100`).
- Any `form_complete` item reads the status, so an expired response is Not yet whatever date window the item also has.

**Timing.** Status is stored (`sync_status!` writes it, `form_response.rb:82-92`), so computing at read time alone leaves reports and badges stale. Two parts: the reason is also computed at read time, so a response is never shown as complete past its expiry; and a recurring job (`FormExpiryJob`, hourly, a line in `config/recurring.yml`, the pattern of `FormScheduleJob`) finds responses of forms with an expiry whose status is `complete` and whose expiry has passed (a join on `forms` and `form_submissions`; the rolling case is `activated_at + valid_for_months * interval '1 month' <= now()`), and calls `sync_status!` on them. Saving a form's expiry runs the same resync for that form, as publishing does (`form.rb:278-282`). No new status or stored expiry timestamp.

**Wording.** The two alerts that explain a reconfirmation assume form or profile in an `else` branch (`form_responses/show.html.erb:17-23`, `edit.html.erb:17-24`), so `:expired` needs its own branch: "This has expired. Please review the answers and sign again." The response page shows "Good until <date>" on a complete response. Showing an item as expiring soon is left to checklists (`next_change_at`, checklists §6.4) and reminders.

**When to use which.** The form's expiry is the form's own truth: the document stops being valid for everyone and everywhere, whatever uses it (a physical is good for a year; a policy is replaced on a date). The completion badge goes, the form is a to-do again, and every checklist sees Not yet. The item's "completed on or after <date>" (§7.2) is a checklist's question: this registration wants a fresh signature, while other uses of the same form accept the old one. The response stays complete, so the badge and other checklists are untouched. If the thing stops being true for everyone, use expiry. If only one checklist wants it fresh, use the window. Both can apply; an expired response is never Done.

Intake owns the expiry columns and `FormResponse#expires_at`; checklists only reads them (checklists §6.4, §13).

**Where it goes.** A new generic branch, `feature/forms-expiry`, based on `feature/forms`: the migration, a concern prepended to `FormResponse` (overriding `reconfirmation_reason`), `FormExpiryJob`, and a form-details field. Upstream files touched (all fork forms files, since forms is a fork feature): `app/views/form_responses/show.html.erb` and `edit.html.erb` (the `:expired` branch), the form details view (the expiry choice), `app/controllers/forms_controller.rb:250` (two permitted params), `config/recurring.yml` (one line). `mcp-forms` gains the two fields on `get_form` and `update_form` if it has one, at app parity. `Form#duplicate!` copies both columns with `dup` (`form.rb:296`). Nothing in upstream's own files changes.

## 8. Approval

### 8.1 Who approves

Team managers (ancestors' included) and admins, as `MembershipApplicationPolicy#update?` allows (`membership_application_policy.rb:28`). No new role and no setting that stops anyone acting. No one approves their own application or a relative's. Delegated organizers are not offered (decision 23).

### 8.2 What the manager sees

The team's applications page (`membership_applications_controller.rb:5`, `index`) gains columns: name, team applied for, source (link, kiosk, own request), submitted, waiting for (guardian, forms, FIRST), checklist counts ("4 of 6 done", opening a row shows each item and who owes it), the "Will also join" preview, flags (possible match, email never opened, no guardian yet), the applicant's message and reviewer notes. Applicant answers show only through the form's own read levels (`FormAccess`).

### 8.3 Bulk approve and deny

Select rows, Approve or Deny. Approve skips rows with an unmet gate or a required pick unchosen and says why per row. Deny asks for a reason, stored as `reviewer_notes` and sent to the applicant. Each decision is audited with the actor, the checklist state and what placement added (§9.6), and fires hooks (§11).

### 8.4 Gating, and no approval

Whether the checklist gates Approve is a registration setting, default "no": managers often meet people before forms are done. When a team needs no approval, the registration adds the membership on verification and the checklist still runs.

### 8.5 What an applicant sees before approval

Nothing of the team. Their pages are `/join/<slug>/me` (status, checklist, the forms they owe, withdraw) and the forms, each limited by its own access. `PersonPolicy::Scope` shows a person with no teams only themselves (`person_policy.rb:5-8`). Exception, upstream's and left alone: `TeamPolicy::Scope` lists `requires_approval` teams to every signed-in user (`team_policy.rb:7-9`), and the public team page shows its managers (decision 24).

Capacity (later): a registration can carry a cap; past it, new entries are held and managers promote them by hand.

## 9. Security

This is the riskiest public surface in the app: unverified people supplying minors' data. A prior audit found many issues in smaller features. Everything here is Phase 1.

### 9.1 No account enumeration

- Every public response is identical for any email: page, status, words, timing target. Only the delivered email differs.
- An existing account gets "You already have an account. Sign in to continue." with a sign-in link. Intake triggers no password reset.
- Matching appears only in the job and on staff screens. The public form never queries `users` by the submitted email and has no "is taken" error.

### 9.2 Rate limits

Rails `rate_limit` on `Rails.cache` (Solid Cache, `config/environments/production.rb:68`), as the kiosk and MCP controllers do (`time_kiosk_controller.rb:7`, `mcp_controller.rb:12`). Defaults, all settings: starting an entry 5 per hour per IP, 3 per hour per email digest, 200 per hour per registration; verification link 10 per hour per IP; resend 3 per entry per day; kiosk 30 per minute per device account. Over a limit the same page says "Try again in a few minutes." without naming the limit.

### 9.3 Bot protection

A honeypot field and a minimum time on the form (signed timestamp; faster than 3 seconds is quietly dropped). An optional challenge behind `Intake::BotCheck`, with a Turnstile adapter off by default (site and secret keys as settings). Self-service with no challenge shows "No bot check" on the setup page. A cap on unverified entries per registration (default 500); at the cap new people see "Registration is busy. Try again later." and managers are told once.

### 9.4 Verify before records

For self-service no `Person`, `User`, `Relationship`, application or form response exists until the email is verified. Before that an entry holds only first name, last name, email and the chosen teams. No children, birthdays, medical data or phones until the person is verified.

### 9.5 Cleanup by date

- Unverified entries expire `intake_entry_days` after creation (default 7) and a recurring job deletes them.
- Closed registrations older than a configured number of days (`intake_archive_days`) are archived: hidden from lists, their entries and counts kept. Archiving is a date filter on the registration list, not a state machine.
- A manager's entries screen shows counts by day and a truncated IP prefix (kept 30 days, shown nowhere else), with Delete selected and Close now.
- A denied-as-spam person with nothing else (no memberships, responses or relationships) can be deleted with their login by an admin, after the screen says what will go. Audited.

### 9.6 Audit trail

Every intake model has `has_paper_trail versions: { class_name: "AuditLog" }`. Public requests have no signed-in user (`application_controller.rb:82` returns the true user), so a public-request concern sets whodunnit to `entry:<id>`; for the kiosk it is the device account. A decision records actor, checklist state and what placement added, so "why was this person approved?" has an answer.

### 9.7 Data protection

Entries encrypt the email and any minor's facts (`encrypts`). Active Record encryption isn't configured today (`grep encrypts app config` finds nothing), so Phase 1 adds keys to credentials; this is the one new secret. Tokens are 128-bit random, stored as SHA-256 digests, single use. Emails carry first names and the team name only. Nothing from an entry goes in URLs, logs or the flash; parameter filtering covers email, guardian email, token and answers.

### 9.8 The kiosk account

The kiosk route lets the signed-in manager do nothing they couldn't elsewhere, and it renders no existing records, so a bystander sees only what the person typed.

### 9.9 Other

Unguessable random slug by default; a closed or unknown slug answers with the same page. Sign-in return paths are internal only. No JSON API for the public. `noindex` on registration pages. Brakeman clean on the branch.

## 10. What this needs from checklists

Requests to `checklists-spec.md`, checked against its §13 "What intake needs from this"; intake designs none of it. Rev. 2 removes everything that depended on a season.

1. **Attach a checklist to a registration** and ask for a person's overall result and item results (label, status, summary, fix link or nil, who owes it: the person or their guardian). Checklists provides stored results (§5.4) and `Checklists.checklist_for(person)` (§13).
2. **Populations:** "pending applicants to a registration's teams"; "members of team X" (for the who-hasn't-come-back filter); "applicants and members" combined so one checklist shows both.
3. **Item kinds, each with its own dates, no season input:**
   - *`form_complete`, signed on or after <date>* (a response whose active submission has `activated_at` on or after the date, `db/schema.rb:394`). One item kind serves signatures and "confirm your information". The date is a field of the item, optionally "N days before today" so it need not be edited each year (checklists §9.1 relative dates).
   - *`form_complete`* also means the form's own expiry (§7.5): a response past its expiry has status `needs_reconfirmation`, so it is Not yet whatever the date window says. The item must read `FormResponse#status` (or `complete?`), never recompute completeness from `activated_at` alone, and should show "Good until <date>" from `FormResponse#expires_at` when present, and "Expired" as the reason when the item is Not yet because of it.
   - *Guardian signature present*: for a guardian-signed form, Not yet with "Needs a guardian linked" and a link to add one while none is linked; "Waiting for <guardian>'s signature" (Almost) once one is (checklists §6.4).
   - *`badge`*, *`has_login`*, *`count`* (dues; the former commitment), *`checklist`* (another checklist).
4. **Acting for a ward:** each item says whether the viewer may act for the subject (`FormAccess.signer_roles`), with the fix link in the subject's context.
5. **Exempt with a reason, who and when**, shown by intake.
6. **A form's audience may be a checklist's population**, so applicants (in no team) are asked the forms the checklist lists (`form_audience_rule.rb:15` targets only team, badge or person today). Checklists §10.3 provides it as a form audience rule target `checklist`, and §5.1 as the population target `applicants`.
7. **A report page** for everyone with an open checklist, with a "not Done" filter; this is "who hasn't come back".
8. **A status-changed event** (the notification `checklist_status_changed.gatherpack` and hook `checklist_results - status changed`, checklists §8.3), so intake notifies without polling.
9. **Batch cost:** statuses for a team's applicants in one query path per item kind; the approval page shows about 200 rows.

Checklists must also not cache a form item's state in a way that outlives `form_responses - incomplete` / the status-changed event (the expiry job fires it). No `Season`, no season input and no stored enrollment row is requested. Last-year information for "new to" is answered by memberships and badges (§6).

## 11. Notifications and hooks

Notices go through `SendEmailJob` (`app/jobs/send_email_job.rb`). Plain, short, overridable on the registration.

| To | When | Says |
|---|---|---|
| Person | Entry created | "Finish joining <team>. This link works for 48 hours." |
| Person with an account | Entry created | "You already have an account. Sign in to continue." |
| Guardian | Entry names them | "<First name> would like to join <team>. Confirm you are their guardian." |
| Person and guardian | An item is waiting on them, at intervals the registration sets | "Still to do: <item>", the guardian's only when the guardian owes it |
| Managers | New applications, as a daily digest | "<n> people are waiting to join <team>." |
| Person | Approved | "You're in. Next: <anything still unmet>." |
| Person | Denied | The manager's reason, or "We can't take your application right now." |
| People on a checklist with due items | Dates the registration sets | "<n> things to do for <team>." |

Nothing goes to a minor's address until a guardian is linked.

Hooks (`GatherPack::HookCatalog`, as `config/initializers/hook_events.rb`): targets `intake_registrations`, `intake_entries`; events `intake_entries - verified`, `intake_entries - expired`, `membership_applications - submitted`, `membership_applications - approved`, `membership_applications - denied`, `intake_registrations - opened`, `intake_registrations - closed`.

## 12. MCP, data, flag, branches, tests, phases

### 12.1 MCP (`feature/mcp-intake`)

Tools allow exactly what the app allows. `decide_membership_application`, `list_membership_applications` and `withdraw_membership_application` already exist; the first gains a deny reason and bulk skip reporting. New: `list_registrations`, `get_registration`, `set_registration_state` (open, close), `list_intake_entries` (no emails), `delete_intake_entries`, `get_application_checklist`, `list_waiting_to_finish`. Not exposed: creating public entries, bot-check secrets, deleting people with logins.

### 12.2 Data (fork migrations, new and reversible, primary DB)

| Table | Columns |
|---|---|
| `intake_registrations` | `team_id`, `title`, `slug` (unique), `description`, `opens_at`, `closes_at`, `self_service`, `kiosk`, `checklist_id`, `gate_approval`, `successor_id`, `created_by_id` |
| `intake_registration_teams` | `registration_id`, `team_id`, `kind` (apply, also_add, pick_one, guardian_also_add) |
| `intake_registration_badges` | `registration_id`, `badge_id` |
| `intake_entries` | `registration_id`, `source`, `email` (encrypted), `first_name`, `last_name`, `facts` (encrypted jsonb), `token_digest`, `expires_at`, `verified_at`, `person_id`, `created_ip_prefix` |
| `intake_household_members` | `entry_id`, `person_id`, `role`, `facts` (encrypted jsonb), `guardian_confirmed_at` |

Added to existing tables: `membership_applications.registration_id` (nullable, indexed) and `source`; `users.intake_login_verified_at`. No existing column changes; `schema.rb` is regenerated. A registration is open when now is between `opens_at` and `closes_at`; there is no state column to drift.

Routes are one block at the end of `config/routes.rb` (no routes seam yet): `/join/:slug`, `/join/:slug/kiosk`, `/join/:slug/me`, `/join/verify/:token`, staff screens under `/registrations` and `/teams/:team_id/registrations`.

### 12.3 Flag and settings

Feature `intake`, `default_enabled: false`, nav under People. Settings (`Settings.register`, group "Intake"; values are cached per process): `intake_kiosk_users_team`, `intake_domain_hints`, `intake_entry_cap` (500), `intake_rate_ip_per_hour` (5), `intake_turnstile_site_key`, `intake_turnstile_secret`, `intake_idle_seconds` (60), `intake_entry_days` (7), `intake_archive_days` (blank, meaning never). Nothing changes for existing teams or applications while the flag is off.

### 12.4 Branches

| Branch | Content | Depends on | Upstream? |
|---|---|---|---|
| `feature/intake` | Registrations, entries, household, both modes, matching, placement lists, application columns, notices, §9 controls | `feature/search-and-add`, `feature/person-fields` (guardianship), `feature/extension-registries` (settings and hook seams) | Yes, generic |
| `feature/intake-checklist` | Checklist panel and approval columns using checklists | `feature/intake`, `feature/checklists` | Yes |
| `feature/forms-expiry` | §7.5: `forms.expires_on`, `forms.valid_for_months`, `:expired` reason, `FormExpiryJob`, form details field, alerts | `feature/forms` | Yes, generic |
| `feature/mcp-intake` | §12.1 | `feature/mcp`, `feature/intake` | No |
| `feature/intake-turnstile` | Turnstile adapter | `feature/intake` | Yes, optional |
| `feature/person-merge` | §4.4 | none | Yes, later |

No seasons branch. Manifest order changes need the owner's approval (AGENT.md rule 8). Branches mention no organization.

### 12.5 Upstream files touched

`config/routes.rb` (one block); `config/recurring.yml` (two lines: entry expiry, archive; a third for `FormExpiryJob` on `feature/forms-expiry`); `app/views/welcome/dashboard.html.erb` (one render line, only if the dashboard card ships); the applications index view for the checklist column (a partial seam if one exists, otherwise a listed view override); `db/schema.rb` regenerated. `MembershipApplication` gets a concern from an initializer, not an edit. Listed in `FORK.md`.

### 12.6 Sample data and tests

`fork/sample_data/features/intake.rb` (Northwind names): an open registration listing two teams, with an also-add list; an unverified kiosk entry; an expired entry; applications waiting for a guardian, with a fully met checklist, with a possible match, and denied with a reason; a returning family with a sibling; a form signed long ago so its checklist item is due again; a person who turns 18 during the checklist.

Tests: placement lists (idempotent, required pick); entry token single use and expiry; matching rules including none across households; identical responses and query counts for an existing and a new email; rate limits per IP, email digest and registration; honeypot and fast-submit drops; entry cap; no person or user before verification; expiry job; params filtered; kiosk gate for a non-manager; an applicant sees only themselves; a guardian acts for a ward but not an unrelated person; bulk approve skips unmet rows; system tests of the kiosk and self-service flows; sample data test, RuboCop, Brakeman.

### 12.7 Phases

1. **Core, self-service:** registrations, entries, verification, matching, applications with source, placement lists, notices, §9. Flag off. No checklist yet; managers see the Forms report.
2. **Checklist:** after `feature/checklists`; approval columns, gating, bulk approve; dates on the items.
3. **Kiosk:** kiosk mode and "Waiting to finish".
4. **MCP and dashboard card.**
5. **Form expiry** (`feature/forms-expiry`), depends only on `feature/forms`. Needed by the checklist only for forms that go stale on their own, such as a yearly physical.
6. **Later:** waiting list, person merge, delegated organizers, a "Sign again" action for forms with `allow_updates` off, and "archive forms older than X" (a date filter on forms; belongs to the improvements outline, `intake-checklists-improvements.md`).

## 13. Decisions

Defaults, 2026-11-06.

1. **No season, year or enrollment model.** Time is a date or range on a registration or a check (product owner). Membership is the record; an organization wanting a per-year roster makes a team for it.
2. **Extend `MembershipApplication`, don't replace it.** Added columns, a concern, placement lists.
3. **A form keeps every response.** "Recent enough" is the item's date, so one form serves several checklists.
4. **Coming back is the same checklist.** No renewal flow or status; due-again items are items older than the item's date. "Who hasn't come back" is a report filter.
5. **A registration is a link, dates, teams "any of", a checklist, and placement lists.** No ways to join; different flows are different registrations.
6. **Placement is three plain lists** (also add, also give, guardian also adds) plus an optional manager pick. Class team is a prompted manager step, with a suggested preselection.
7. **Verify before records** for self-service. The kiosk creates records at once, marked unverified, because a manager is present.
8. **One flow, two skins.** Kiosk and self-service differ in access and in what they ask.
9. **No signatures, medical data or birthdays on a shared screen.**
10. **Identical responses for every email.** Matching only in the job and on staff screens.
11. **Matching never merges.** Login email attaches; name matches are held; default is keep separate.
12. **"Confirm your information" is a form** checked by date. No second place to edit a profile.
13. **Approval doesn't wait for the checklist by default;** a registration can gate it.
14. **Intake removes no one.** It lists who hasn't come back; managers act.
15. **Applicants see only themselves.** Upstream's visibility of approval-gated teams stays.
16. **Nothing to a minor's address** until a guardian is linked.
17. **Flag off by default.** No forms change in phase 1.
18. **Every date is configuration:** open, close, entry retention, archive age, reminders. Copying proposes shifted dates for a person to confirm. No month is in code, including HBR's.
19. **Date housekeeping where it fits intake:** unverified entries expire, old closed registrations archive by a date setting.
20. **Forms may expire by date or by age** (product owner, 2026-11-06): a form's own optional rule, `expires_on` or `valid_for_months`, using the existing re-confirmation state. A checklist's window is separate. Use expiry when the response stops being true for everyone; use the window when only one checklist wants it fresh (§7.5).
21. **No membership end date.** Memberships stay without dates (`db/schema.rb:609`); alumni and yearly rosters are teams, and the audit log answers history.
22. **A minor's first email goes to the guardian.** The minor's own address gets mail after the guardian confirms (§5.4).
23. **Managers and admins run registration.** No delegated organizer role; the existing approval policy stands (§8.1).
24. **Approval-gated teams stay visible as upstream shows them.** Intake does not change team visibility (§8.5).

## 14. Upstream and table notes

`memberships` has no date columns (`db/schema.rb:609`), so "joined on" and "left on" are not recorded. Decision 21 leaves it so.

## 15. Open questions

None.

## Appendix A: HBR setup

Configuration only. None of this is in the generic branches. No season model; dates are on records.

- **Registration.** "Join Team 1747" with its open and close dates set when the callouts start, self-service and kiosk on, owned by the main team. Next year's is "Copy registration" with dates shifted and confirmed.
- **Teams people may apply to.** "Team 1747 - Students", the adult mentors and volunteers team, "Parents". Students and adults see the same list; the checklist (below) is what differs. If the questions differ enough, two registrations.
- **Also add / give.** Students: "also add a guardian to Parents". The class team ("Team 1747 - Class of <year>") is the manager's pick at approval, preselected from the graduation year field when a team's name matches. A "<year> Rookie" badge is given by the manager when approving a newcomer; "returning" students come in through the checklist only.
- **Checklist.** participation agreement and medical release (guardian-signed, `form_complete` on or after the date HBR chooses, today's `allow_updates` on), "confirm your information" form on or after the same date, "Registered with FIRST" and "FIRST consent" badges (synced by script from FIRST's roster), dues as a count item or a badge, if the books record them. HBR changes the date each year; a returning member sees those items Not yet with answers pre-filled.
- **Who hasn't come back.** The checklist's report filtered to people whose overall isn't Done, on last year's roster.
- **Kiosk accounts.** The existing kiosk accounts team; callouts use the kiosk address on a laptop in the room.
- **Before the first run.** Match students and guardians by email first. The old import scripts in `~/dev/gatherpack-import` aren't re-run.
- **Forms that go stale.** The physical form sets "12 months after signing"; the participation agreement sets nothing and relies on the checklist date.
- **Google Form.** Stays until the first intake registration is verified; the website link then changes to the registration link.
- **Hook examples.** A welcome email on approval; a notice to the events coordinator when a mentor is approved.
