# Improvements as a function of intake and checklists

Status: outline rev. 3, 2026-11-06. Nothing here is built. Companion to [`membership-intake-spec.md`](membership-intake-spec.md) and [`checklists-spec.md`](checklists-spec.md) rev. 3. Rev. 3: the requirements engine and Commitments are one feature, **Checklists** (a commitment is a count item inside a checklist); terms, branch names and section references follow that spec, and the outline carries no dates, only dependency order. Code facts checked at integration `49609326`.

Rev. 2: no seasons. The first outline leaned on a `Season` model, season enrollments and a rollover assistant. All of that is gone. Time is a date or a date range on a record or a check, and a per-year roster is a team if an organization wants one. Date housekeeping (archiving, expiry, age filters, retention) is now its own group and the top of the ranking.

Each item is a paragraph, not a spec. Size: S = days, M = one to two weeks, L = more. Scope: **generic** (upstreamable, no HBR words) or **fork-only**. HBR facts are in the last section.

## 1. Ranking

| Rank | Item | Size | Why |
|---|---|---|---|
| 1 | H1 Archive by date, one pattern | S-M | Direct ask; forms, sign-up sheets and checklists already have `archived`, so the pattern exists |
| 2 | F1 One date control | S | Every spec adds "on or after / within the last N"; build it once |
| 3 | H2 "Older than X" filters on list pages | S | Makes H1 usable and finds stale things without a new screen |
| 4 | D1 Record health checklist | S | Missing birthdays and guardian links decide who needs a guardian |
| 5 | S1 "You still need" at the kiosk | S-M | Replaces the planned Reminders widget and the logic copy it warned about |
| 6 | E1 Clearances as dated attestations | S | Background checks and training lapse; no table change needed |
| 7 | F2 One population shape | M | Four near-copies of the same rule table today |
| 8 | H3 Bulk copy with dates shifted | S-M | Replaces the "start next year" assistant with the same list-page bar as H1 |
| 9 | D4 List import | M | Retires the FIRST roster script; reusable |
| 10 | S4 One reminder per person | M | Intake, checklists and forms each add reminders |
| 11 | F4 Person merge, pulled forward | M | Kiosk makes duplicates likelier; new tables add person columns |
| 12 | H4 Retention purges by age | M | Needs a policy first |
| 13 | E5 Trip packet from a recorded list | S-M | "Record this list" now ships first; add the roster print |
| 14 | E8 Event safety sheet | M | Medical and emergency data where leaders need it |
| 15 | F5 Seams (jobs, routes, cards) | S | Fewer upstream files per feature |
| 16 | F3 Team queries without Ruby recursion | S | Performance for checklists and approval |
| 17 | S3 Registration page: funnel and blockers | S | Extends intake's entries screen |
| 18 | S5 A roster is a checklist with no items | S | Retires the roster Page |
| 19 | D2/D3 Duplicate queue; guardian link fix | M | Data quality |
| 20 | E2/E3/E4/E6/E7/E9 | S-M each | Onboarding, bulk move to alumni, waitlist, statements, dues, statistics |
| 21 | MCP parity | S per branch | Rides with each branch |

## 2. Date housekeeping (first-class)

One idea, applied the same way everywhere: **time is a date on the thing, and anything old can be found, archived, copied forward or purged by date.** The rule from the product owner: dates and date ranges, not rigid constructs.

### F1. One date control

A small value object and form partial for the choice the checklists spec already defines (§9.1): **on or after** [date], or **within the last** [N] [days | months], resolved against "now" or an as-of moment. Used by checklist items, form expiry display, list filters (H2), archive and retention settings (H1, H4) and intake's retention fields. One parser, one explanation sentence ("within the last 12 months, since 12 Nov"), one test file. Size S. Generic. **Touches.** Gives checklists §9.1 and intake §7.2 the same widget; intake's `intake_archive_days` and `intake_entry_days` become the same control.

### H1. Archive by date, one pattern

**What.** Today forms and sign-up sheets have an `archived` status (`form.rb:27`, `signup_sheet.rb:28`; `visible` scopes hide them), person fields have `archived_at` (`person_field.rb:29`), commitments have only `starts_on`/`ends_on` and no archive (`db/schema.rb:236-250`), and the new checklists and intake registrations each plan their own (checklists §9.7, intake §9.5). Count items live inside their checklist, so a commitment is archived with the checklist that wraps it (checklists §11.1), not on its own. Make it one pattern:

- **Meaning.** Archived items leave menus, pickers and dashboards, stay openable and searchable, and can be restored. Nothing is deleted. Where a model has an `archived` status, use it; where it has none, add a nullable `archived_at`. The screens look identical. Checklists already have `archived` (checklists §5.1).
- **By hand, in bulk.** On each list page, the date filter (H2) plus a bulk bar: **Archive selected** and, under the Archived filter, **Restore selected**. A preview first: "12 forms will be archived. 2 skipped: still used by <checklist>." Used-by checks reuse the "protected on delete" references the specs already add; a checklist another checklist requires is skipped and flagged (checklists §9.7).
- **Automatically, if wanted.** One setting per type, "Archive automatically N days after it ended or closed", blank meaning never, run by one nightly job that walks a small registry (`Housekeeping.register(Model, ended_on: ->{}, archive: ->{})`). A feature registers itself; none edits the job. Off by default (rule 10).
- **What "ended" means.** Forms: `closes_at` (`db/schema.rb:420`) or last response. Sign-up sheets: last event date. Checklists: the window's end (count items inside move with their checklist). Registrations: `closes_at`.

Size S-M. Generic. **Touches.** Generalizes checklists §9.7 (archive checklists ended before a date; prune results) and intake §9.5's archive paragraph by registering them in this pattern; resolves the "archive forms older than X" deferral in intake §12.7 phase 6. Answers the stale-list problem for a team running years of forms and sheets.

### H2. "Older than X" on list pages

A shared filter partial (F1) on forms, sign-up sheets, commitments, events, announcements, checklists, registrations and applications: "Ended / closed / last activity: on or before [date] or more than [N] months ago". Ransack already handles date predicates; this is the control and a saved default. People get "no activity since": no punch, check-in, sign-up or form answer after a date, computed from existing tables, not a new column. Size S. Generic. Used by H1 and H4.

### H3. Bulk copy with dates shifted

The same bar gets **Copy selected, dates shifted by [1 year]**. It uses what the specs already define for one record: intake "Copy registration" (dates shifted, confirmed), "Copy checklist" (checklists §9.3: date shift plus an Old → New table for anything named with a year; count items get new commitment rows), `Form#duplicate!` (`form.rb:296`). One shared concern provides the shift and replacements table; each model says which date fields shift. Copies are drafts. Size S-M. Generic. **Replaces** the "start next season" assistant of the first outline: no wizard, no registry of steps, no season; the person selects what to carry forward on the lists they already use.

### H4. Retention purges by age

**What.** Intake purges unverified entries after 7 days (§9.5). Nothing else is bounded, and these specs add data about minors. Define purges as ordinary, previewed, admin-only actions on the same list pages: denied applications older than a date, access-log rows (E8), results of archived checklists (a cache, safe to drop; checklists §9.7), and the medical and emergency answers of people with no activity since a date (H2). A purge removes data, not the person or their history, shows exactly what will go, asks for confirmation, and writes an audit entry. Nothing runs by itself. Size M. Generic. **Needs** a decision on the ages (list below).

### H5. Form expiry (already specced)

Intake §7.5, branch `feature/forms-expiry`: `forms.expires_on` or `forms.valid_for_months`, the `:expired` reconfirmation reason, `FormExpiryJob`. Not redesigned here. Two cross-references. Expiry (the response stops counting) is a different thing from H1 (the form is hidden); a form can be archived while old responses stay valid, and an expired response never archives a form. And the "Good until <date>" line should use F1's sentence, so forms, checklists and reminders say the same thing.

## 3. Foundations

### F2. One population shape

"Who does this cover" is written four times: form audience rules (`form_audience_rule.rb:16`: team, badge, person), sign-up audience rules, commitments (owing team and badge minus exempt badge, `commitment.rb:170`), checklist rules (adds applicants). The decided "people covered by checklist X" for forms makes a fifth, and count items replace commitments' own owing columns with the checklist population (checklists §11.2), so the commitments copy is already folding in. Add a registry of target types and one evaluator for include/exclude lists. Do not migrate existing tables: new owners use it, and forms and sign-ups add targets by registration instead of enum edits (`form_audience_rule.rb:16`, `signup_position_rule.rb:19`). Size M. Generic. **Touches.** Turns the two connector edits in checklists §10.3 into registrations.

### F3. Team queries that do not recurse in Ruby

`Team#all_descendant_ids` recurses one query per child (`team.rb:47-49`) and the Pages repeat it (`pages/team-roster.html.erb:18`, `safety-training-report.html.erb:15`). Checklists must evaluate 200 people in a bounded number of queries (checklists §12.6). Add `Team.subtree_ids(ids)` (one recursive query), `Person.on_teams(ids, managers:)` and `Person.visible_to(viewer)`. Size S. Generic; a good first upstream PR.

### F4. Person merge, earlier, with a registry

Merging is a script today (`~/dev/gatherpack-import/merge_person.rb`); intake lists it as "later" (§4.4, §12.7). Move it up: the kiosk makes duplicates likelier, and checklists and intake add `person_id` to at least six tables (results, excuses, attestations, entries, household members, applications' new columns; adjustments already have one). Add `PersonMerge.register(table, column)`, which each feature calls, and a test that fails when a table with `person_id` is in neither the registry nor a short exempt list. The same registry says what "has nothing else" means for deleting a spam person (intake §9.5). Admin-only, previewed, one audit entry. Size M. Generic.

### F5. Seams for jobs, routes and cards

Every feature edits `config/recurring.yml` and `config/routes.rb` (intake §12.5, checklists §12.3); `routes_proc` is commented out (`config/routes.rb:276`). Add a loader for `config/recurring.d/*.yml` and enable `routes_proc`. For cards, register a section through `MyGatherpack.register_section` ([`my-gatherpack-spec.md`](my-gatherpack-spec.md) §6.1) instead of editing `welcome/dashboard.html.erb`. Size S. Generic. Also gives H1's nightly job and `FormExpiryJob` a home that edits no upstream file.

### F6. Encryption for new sensitive columns only

Intake adds the first `encrypts` (none exist today) and so the first credentials. Do it once with a short runbook (generate, store, rotate, what a lost key means for backups). Do not encrypt existing columns: birthday is searched and ranked (`person.rb:126-136`). Size S. Generic.

## 4. Data quality

### D1. Record health, as a checklist

The guardianship age limit needs a birthday: with none, a person counts as a minor by a global setting (`person.rb:131-135`). So missing birthdays and guardian links decide who is asked for a guardian's signature. Build "Record is complete" as an ordinary checklist: `age` (not yet "No birthday on file"), `has_login`, `person_field` (graduation year), and `has_guardian` moved from "later" into the first version (checklists §1.2). The "confirm your information" form on the joining checklist collects the birthday (family-level field, `person_field.rb:57`), so the list drains as people complete it. Size S. Generic.

### D2. Duplicate queue

Intake matches only when an entry is verified (§4.3). Add a nightly sweep that fills a "Possible duplicates" list using the `find_duplicate_people` logic, with Keep separate (remembered), Link and Merge (F4). Size M. Generic.

### D3. Guardian link as a fix link

For `has_guardian` Not yet, the fix is a page "Add a guardian" that sends intake's guardian confirmation email (§4.2). Emergency contacts use the weaker relationship of [BL-023](../backlog/BL-023-contact-relationships.md). No renewal step is needed. Size M. Generic.

### D4. List import: match, review, apply

The FIRST roster is granted by a local script (`~/dev/gatherpack-dev-data/first_roster/sync_first_roster.rb`, PDF parsed outside). The same shape recurs: training completions, background-check results, a school's list. Make it one screen: paste rows (name, optional email), see matched / ambiguous / unmatched, choose for the ambiguous, pick the outcome (give a badge, set a field, or record an attestation, E1), apply, and keep the run in the audit log. PDF parsing stays a local script that emits rows. Size M. Generic. **Retires** the grant half of `sync_first_roster.rb` and part of `register_placeholders.rb`.

## 5. Surfaces

### S1. "You still need" at the kiosk, from the checklist

[`kiosk-spec.md`](kiosk-spec.md) §7 plans a Reminders widget that re-implements FIRST, safety training, login and forms checks as a Page script, and says copying the Eligibility logic "would drift". `Checklists.checklist_for(person)` (checklists §13) is a cheap read of stored results. Replace the widget's logic with a native kiosk slot listing a person's unmet items. The kiosk is a shared screen: each item has `show_on_kiosk`, default off; items are one short line, no numbers; managers see nothing. Size S-M. Slot generic, widget fork-only.

### S2. One list on My GatherPack and the family page

Checklists §10.4 and intake §7.4 each add a to-do. Make them one section: a card per person (the viewer and wards), one ordered list merging forms, sign-ups, count items and unmet items, with a single "Do this next". Guardian wording only when the viewer is a guardian. Size S. Generic.

### S3. Registration page: funnel and blockers

Intake already shows entries by day and "Waiting to finish". Add counts down the funnel (opened, entries, verified, applied, approved, checklist Done) and "who is blocking" (waiting for guardian, a badge, unopened invitation older than 3 days). It reads stored data; nothing new is stored. "Who hasn't come back" is the joining checklist's report filtered to Not yet (intake Appendix A). Size S. Generic.

### S4. One reminder per person

Intake §11 (reminders at set intervals), checklists open question 2 (Done to Not yet) and app-feel §8.8 (forms due, monthly reminders of what people still owe, which become count items) each send their own. A family would get several. Add a collector: features register what a person still owes, and one job sends at most one "Still to do" message (email, plus phone through `PushTopics` if opted in) listing everything with fix links, guardians getting their wards' items. The monthly reminder job already works this way. Add "Message these people" on any report filter that uses it. Off by default. Size M. Generic.

### S5. A roster is a checklist with no items

`team-roster.html.erb` (82 lines) needs only a population, columns, sort, filters and print. A checklist with zero items is a roster; the contact column appears only where the viewer can already see the guardians (checklists §14.4). Retires the Page and uses the shared print styles (also helps [BL-010](../backlog/BL-010-long-tick-box-lists.md)). Size S. Generic.

### S6. Paper fallback for the open house

A printable one-page sheet with the registration's address as a QR code and a paper sign-in list to type into the kiosk later. Wi-Fi in a gym fails. Size S. Generic.

### S7. Send invites from the report

`has_login` Not yet says "ask a leader to invite you". Give leaders a button that sends intake's invitation email (§5.2). Size S. Generic.

## 6. Things nobody is thinking about yet

### E1. Clearances as dated attestations

Background checks and youth-protection training lapse, and a badge assignment has no date or expiry (`db/schema.rb:94-102`). Do not add one. Use the `attested` kind (checklists §6.6): a manager records "background check cleared" for a person; the check reads "attested within the last 24 months" (F1). The history stays as rows, a renewal is a new attestation, and the clock refresh makes the lapse appear on the day (`next_change_at`, checklists §8.2). An "expiring in 30 days" item rides on S4. D4 can record attestations from a provider's list. No change to badges or any upstream table. Size S. Generic.

### E2. Volunteer and mentor onboarding

A registration whose teams and joining checklist suit adults (intake §1.2). Add one thing: a list view where a manager attests many people at once ("orientation attended"), never for oneself. Size S. Generic.

### E3. Bulk move to an alumni team

Without membership dates there is no "former member". Alumni are a team (the product owner's rule). Add a bulk action on a team's people list: **Move selected to another team**, with a preview and the H2 "no activity since" filter. A manager acts; nothing automatic. Size S. Generic. (No membership end date; decision 3.)

### E4. Waitlist without an enum change

Intake lists a waiting list as later. Use a nullable `waitlisted_at` on the application and a cap on the registration counted from placed memberships, with a Promote action, rather than extending upstream's status enum. Check first whether sign-up slot capacity (`signup_slot.rb`) should share the promote logic. Size S-M. Generic.

### E5. Trip packet from a recorded list

"Record this list" ships in the first checklists release (checklists §9.4, decision 18). The addition: from a recorded list, print a roster for the trip's organizers with guardians' phones and the E8 emergency data, and let a sign-up sheet position require the checklist (checklists §10.3) so the sign-up page can say why someone cannot take a seat, using the failing item's fix link. Size S-M. Generic.

### E6. Participation statement

Students ask for a letter of hours and years of service. Provide a page for a person and a date range ("from [date] to [date]") reading time clock hours, check-ins, count items done and team memberships with "since" taken from the membership's `created_at` (`db/schema.rb:609`) or the audit log. "Left on" is only known from the audit log, so say so on the page. No certificate designer; a clean print page and CSV. Size S-M. Generic.

### E7. Dues, fees and waivers

Start with what exists: dues are a count item in dollars or an attested item recorded by the treasurer; a waiver is an excuse, whose reason only managers and admins read (checklists §7). A Stripe gateway exists (`app/models/gateway/stripe_gateway.rb:2`) for in-app payment later. [BL-011](../backlog/BL-011-accounting-integration.md) decides the books; do not pick a side. Size S now, L later.

### E8. Event safety sheet

Families sign medical releases and list contacts; the leader at an away event needs them on paper or a phone. Add a sheet for an event or sign-up roster: attendee, medical and dietary fields, emergency contacts, guardians' phones, required forms met. Visible only to the event's organizers and named chaperones, from a day before to a day after, printable. Every opening is logged: PaperTrail records writes, not reads, so this needs a small access-log table (H4 purges it by age). Size M. Generic.

### E9. Participation statistics

Counts for sponsors and schools in a date range: people with a membership created in the range, hours, outreach events, check-ins. Counts only, cells under 5 hidden, CSV export, no names. "New versus returning" is not reliable without membership dates, so it is left out. Size M. Generic.

## 7. Retiring Pages and scripts

| Today | Becomes | After |
|---|---|---|
| `eligibility-report.html.erb` (700 lines) | One checklist (checklists §14) | After parity (checklists §14.6); the Page stays as fallback |
| `attendance-report.html.erb` (218) | Attendance item drill-down | With `feature/checklists-attendance` |
| `safety-training-report.html.erb` (96) | Checklist with one badge item | With the core |
| `outreach-report.html.erb` (200) | Outreach count item and its drill-down | With `feature/checklists-count` |
| `team-roster.html.erb` (82) | Roster checklist (S5) | With the core |
| Kiosk Reminders widget (planned) | Native slot (S1) | With the core |
| `sync_first_roster.rb` (grant half) | List import (D4) | D4 |
| `merge_person.rb` | Person merge (F4) | F4 |
| Google Form and `enrollment_read.rb` | Intake | After the first verified registration |
| Per-year edits at the top of Pages | Checklists with dates, copied by H3 | With the core |
| `scan-cards.html.erb`, `assign_scan_tokens.rb` | Stay | Placement does not issue cards |
| `academic-eligibility`, `clocked-in-report` | Stay as Pages | Bulk editor; live view |

History scripts (Ditto and sign-up migrations, concessions fixes) are never re-run.

## 8. MCP at parity

Tools allow exactly what the app allows. Intake §12.1 and checklists §12.4 list theirs (`list_checklists`, `checklist_status`, `checklist_results`, `add_credit_adjustment`, `remove_credit_adjustment`, `excuse_item`, `remove_excuse`, `attest_item`; the four commitment tools stay as aliases). Additions, each with its branch:

| Tool | App equivalent |
|---|---|
| `list_stale_items` (read; type and F1 date) | H2 filters |
| `archive_item`, `restore_item` (one record, same permission as the app) | H1 bulk bar, one at a time |
| `copy_registration`, `copy_checklist`, `copy_form` (drafts; checklists §12.4 names no copy tool, so `copy_checklist` is an addition) | H3 |
| `record_list` (not in checklists §12.4; an addition) | Record this list |
| `people_meeting` (a checklist and a status, within the caller's view; an addition) | Report filter |
| `list_possible_duplicates` (read) | D2 |
| `message_people` | S4 button |

Not exposed: merge, purges, the access log, safety sheet content, bulk import.

## 9. Risks

- **Public pages.** Intake §9 covers the controls. Additions: a printed QR (S6) must reveal nothing if the slug leaks (a closed registration answers like an unknown one); the safety sheet (E8) is the most valuable page for an attacker, so it is never indexed or cached by the service worker ([`app-feel-spec.md`](app-feel-spec.md) §7.2) and is logged on open.
- **Write storms.** Checklists invalidate by change (checklists §8.2). Bulk actions here (H3 copies, E3 moves, a D4 import, approving a group) touch many people. Let a bulk operation pause refreshes and queue one per checklist at the end; test with 150 people.
- **Feedback loop.** Approval creates a membership, which invalidates results, whose status change intake listens to. Intake's handler must be idempotent and run in the refresh job, never in a user's save.
- **Archiving something in use.** H1 must refuse or flag anything another record refers to (a form or badge on a checklist, a checklist another one requires). The preview says so.
- **Rows for people who may not exist.** Kiosk entries create unverified people, and checklists create results for them. Expiry, deletion and merge must take results, attestations and entries along (F4 registry; one test per table).
- **Configuration sprawl.** Fewer constructs now, but still a registration, a checklist, forms and sign-up sheets each year. Names carry the year; H2 finds stale drafts; "Setup problems" appears on checklists and registrations.
- **Upstream acceptance.** Large surface, one maintainer, and the audit disclosure is unanswered. Slice the pull requests: seams (F5), team queries (F3), date control (F1), the archive pattern (H1), then the checklists core and connectors. Send nothing until upstream has caught up.
- **Badges as flags.** Sync badges (`2027 FIRST Registered`) are facts a script writes; fine. Clearances use attestations (E1), not badges. Dues and quotas are count items, not badges.

## 10. Order of work

Dependency order only (checklists §17 for the engine's own order); when anything ships is the product owner's call.

1. Independent and small: F1 date control, F3 team queries, F5 seams, F6 keys. `feature/forms-expiry` (intake phase 5) has no dependency on the rest.
2. `feature/checklists` core. Then H1 and H2 on forms and sign-up sheets (existing `archived`), and D1 as a checklist.
3. `feature/checklists-attendance`, then `feature/checklists-count` (needs `feature/commitments`) with the edits it brings to the commitment branches (checklists §11.4). H1 then covers checklists, and count items inside them.
4. `-person-fields` and `-forms`, parity against the Page (checklists §14.6), then `feature/mcp-checklists` and `feature/my-gatherpack-checklists`. S1 and S2 need these.
5. F2 population shape and F4 person merge, before intake's kiosk. Predicates (`-signups`, the form audience target) follow F2. Then H3, E1, E5, E8.
6. Intake core and checklist panel (`feature/intake`, `feature/intake-checklist`), D4 list import, S4 reminders.
7. Intake kiosk, S6 paper fallback, S3 funnel. The Google Form retires after the first registration's entries verify.
8. H4 purges once ages are decided; D2 duplicates; E3, E6, E9, E4 and E7 as asked.

## 11. Considered and dropped

A `Season` model, season enrollment rows, named season dates, a start-next-season assistant, a season close-out wizard, an expiry column on badge assignments (dated attestations do it), "interests" placement conditions (intake placement is three plain lists), per-language registration text (no evidence of need).

## 12. Decisions

Made, not open. Earlier decisions: no seasons; every date is configuration; one feature, Checklists, with commitments as count items; excuses are for managers and admins only; "Record this list" ships in the first release; carry-over is set per attendance rule. Upstream pull requests go in the slice order in §9 once upstream has caught up. Dues start as a count item or a treasurer-attested item.

1. **Auto-archive is a setting, default off.** One setting per type: "Archive automatically N days after it ended or closed", blank meaning never. Manual bulk Archive and Restore are always available.
2. **Retention purges are previewed and admin-run, never automatic.** The ages are settings with conservative defaults: denied applications 12 months, access-log rows 24 months, medical and emergency answers of people with no activity 36 months. Blank disables a purge.
3. **No membership end date.** Alumni are a team; "since" comes from the membership's `created_at` and the audit log.
4. **Clearances are dated attestations** by a manager ("within the last N months", N set on the item). No change to badges.
5. **Kiosk "you still need" lines** are off per item by default (`show_on_kiosk`). The stopgap Reminders widget is skipped.
6. **Reminders are one combined message per person per day.** A change from Done to Not yet sends nothing unless a checklist turns that on; it is a setting, default off.
7. **The event safety sheet** is for the event's organizers and named chaperones, from a day before to a day after the event, and every opening is logged.
8. **Person merge comes before the kiosk** in the order of work, with the registry rule for new tables.

## Appendix: HBR-only facts

- Class teams (`Team 1747 - Class of 20NN`) are ordinary teams, created by hand when needed; the manager picks one at approval (intake §6).
- The FIRST roster arrives as a PDF; the parser stays a local script that emits rows for D4. `2027 FIRST Registered` and `2027 FIRST Consent Signed` stay facts the `badge` item reads.
- Scan cards are `1747` plus eight digits, printed from the existing Page.
- Dues are recorded outside GatherPack (Zeffy) and credited by hand until the books decision.
- Mentor clearances (background check, youth-protection training) are E1 attestations on the adult team's checklist; students' safety training badge stays as is.
- Academic eligibility and Who's Clocked In remain Pages.
