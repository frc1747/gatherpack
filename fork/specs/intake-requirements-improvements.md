# Improvements enabled by Intake, Requirements and Seasons

Status: outline rev. 1, 2026-11-05. Nothing here is built or specced in full. Companion to [`membership-intake-spec.md`](membership-intake-spec.md) and [`requirements-spec.md`](requirements-spec.md). Code facts checked at integration `49609326`; where this outline says "no X today" it names the file that shows it.

The question asked: what else is useful, or benefits the platform, because these three things exist. This outline ranks the answers. Each item is a paragraph, not a spec. An item that gets chosen becomes a spec or a backlog entry (`BL-NNN`) of its own.

Assumes the reconciliation already decided: a small `Season` model in `feature/seasons`; requirement sets take their window from a Season when one is chosen; "profile confirmed this season" is a renewing confirm-your-information form read by `form_complete`; intake listens to `requirement_status_changed.gatherpack`; form audience rules gain "people covered by set X".

Sizes: S = a few days, M = one to two weeks, L = more than two weeks, as one person with an agent. Scope: **generic** (written to upstream's standards, no HBR words) or **fork-only**. Everything HBR-specific is in the last section.

## 1. Ranking

Ranked by value to the team for the 2027 season divided by effort, with items that other items stand on first.

| Rank | Item | Size | Why this rank |
|---|---|---|---|
| 1 | F1 Season enrollment record | M | Intake's own open question 1; alumni, retention, letters and "new to" all read it |
| 2 | F3 One population shape | M | Four near-copies of the same rule table today; decision (4) adds a fifth |
| 3 | F2 Start-next-season assistant | M-L | The "copy" step is in three specs; one place stops the evening of scripts |
| 4 | D1 Record health (fix list) | S | Birthdays and guardian links decide who needs a guardian; cheap once sets exist |
| 5 | S1 "You still need" at the kiosk | S-M | Replaces the planned Reminders widget, and the logic copy it warned about |
| 6 | E1 Clearances that expire | M | Mentor background checks and training expire; badges cannot say so |
| 7 | D4 List import (FIRST roster and others) | M | Retires the roster script; reused by clearances, training, school lists |
| 8 | S4 One reminder per person | M | Three specs each add their own reminder; people will get three emails |
| 9 | F5 Person merge, pulled forward | M | The kiosk makes duplicates likelier; every new table adds a place to merge |
| 10 | E5 Trip rosters from eligibility | M | "Record this list" is needed by the first away event, not "later" |
| 11 | S3 Season page for managers | M | Funnel and "who is blocking" in one place |
| 12 | E8 Medical and emergency sheet at events | M | The reason a family trusts the forms |
| 13 | F7/F8 Seams for jobs, routes and cards | S | Fewer upstream files touched by every feature |
| 14 | E3 Season close-out and alumni | M | Intake never removes anyone; someone must, with a preview |
| 15 | S5 Rosters as sets with no requirements | S | Retires the roster Page without a new mechanism |
| 16 | E2 Volunteer and mentor onboarding | S | Almost all configuration; one small addition |
| 17 | E10 Season statistics | M | Sponsors and schools ask the same questions each year |
| 18 | E9 Retention and archiving | M-L | A policy decision first; code second |
| 19 | E7 Dues, fees and waivers | L | Wait; start with treasurer attestation |
| 20 | E6 Participation letters and awards | S-M | Falls out of F1 |
| 21 | E4 Waitlist without an enum change | S-M | Replaces intake §10.6's approach |
| 22 | MCP parity | S per branch | Rides along each branch |

## 2. Foundations that both specs lean on

### F0. Split `feature/seasons` so nothing important waits on forms

Intake §17.2 puts `feature/seasons` on top of `feature/forms`. Requirements §11.1 says its core depends on nothing and is written to go upstream unchanged. If a requirement set takes its window from a Season, the core would depend on a branch that depends on forms.

Decision: two branches. `feature/seasons` is the model, `Season.current(team)`, named dates (F1b) and the rollover-step registry (F2). It is based on `upstream/main`. `feature/seasons-forms` holds `Form#renews_each_season`, the reconfirmation reason and the rollover job. Requirements and intake then take a soft dependency: a `season_id` that is used when the Season class exists, as the spec already says (intake §9.1, requirements §12). Size S. Generic.

### F1. A season enrollment record

**What.** One row per person per team per season: "was on this team for the 2027 season, joined as <way>, renewed on <date>". Today there is no record that someone belonged to a team in a past season: memberships carry no dates (`db/schema.rb:609-619`), teams have no season or archive (`db/schema.rb:1092-1105`), and a person who leaves loses the row. Intake's "new to" test and "renewed for the season" fact both need it, and intake's default is a badge ("2027 Season Rookie", "<season> member", §8 and open question 1).

**Recommendation.** Make it a row, written by intake when a person is approved or renews, and by a one-time backfill from last year's roster. Not a badge: it is a fact about a season, it will be wanted for every past season, and a badge per year per fact is the status-flag habit this project is trying to leave (BL-003's reasoning, requirements §1.1). Placement still may grant a badge where a person asks for one; the check "new to" reads the table.

**Benefits.** Managers (who returned), students and families (years on the team), the organization (alumni, letters, statistics). **Depends on** `feature/seasons`. Size M. Generic.
**Touches.** Resolves intake open question 1. Replaces the "season badge" pieces of intake §8 and Appendix A (rookie badge, season member badge). The Eligibility set stops needing a "Rookie" badge: the exclusion becomes "enrolled in no earlier season" (requirements §5.2, §13.2 row 5).

### F1b. Named dates on a Season

**What.** A Season holds a few labelled dates beyond start and end: registration opens, kickoff, a dues deadline, first away event. Requirements read them as due dates ("Missed after <date>"), intake reads them for reminders (§12), widgets read them for countdowns. Today each of those is typed again in a Page's settings block or a widget (`pages/kickoff-countdown-widget.rb`) and in `due_on` fields.

Size S. Generic. **Retires** the hard-coded kickoff date in the countdown widget and the `season_start_month` Page setting (requirements §2).

### F2. A "Start next season" assistant

**What.** One screen, run once a year by a manager, that walks the list of everything season-bound and copies each with the window shifted: the registration (intake §3), requirement sets with the badge/form/commitment substitutions proposed from year-bearing names (requirements §9.3), forms switched to renew, commitments, sign-up sheets, and the class teams (create the new freshman class team, rename nothing). Each feature registers its own step, `Seasons.register_rollover_step(:requirements, ...)`, so a disabled feature adds no step and a new feature joins without editing this one.

The screen shows "created", "needs a choice" and "skipped" per step and creates everything as a draft. It is the answer to configuration sprawl (§8): every season-bound object is born in one place and can be listed together ("Everything for 2028").

**Benefits.** The person who runs the season. **Depends on** `feature/seasons` and each feature's own copy action (intake and requirements both already specify one). Size M-L, mostly the steps. Generic.
**Touches.** Subsumes intake "Copy registration" and requirements "Copy set" as the entry point (their buttons stay). Reduces the open question in [`mcp-expansion-spec.md`](mcp-expansion-spec.md) §11 (copy a sheet with new dates) to "copy is a button, and so a tool". Retires, for HBR, the per-year scripts for class teams and rookie badges (`rookie_badges_class_2030.rb`, `safety_badges_new_students.rb` in `~/dev/gatherpack-import`).

### F3. One population shape

**What.** "Who does this cover" is written four times: `FormAudienceRule` (`form_audience_rule.rb:16`: team, badge, person), sign-up audience rules, commitments (owing team and badge minus exempt badge, `commitment.rb:170`), and `requirement_rules` (adds applicants). The reconciliation adds "people covered by set X" to forms; intake needs "returning members" and "pending applicants". Fix it once, small: a registry of target types and one evaluator that takes a list of include and exclude rules and returns people.

Do not migrate the existing tables. New owners (requirements, intake) use it; forms and sign-ups add target types through the registry instead of enum edits (`form_audience_rule.rb:16` and `signup_position_rule.rb:19` are the two enums the requirements connectors would otherwise edit). The existing tables get a thin adapter. Size M. Generic.
**Touches.** Turns the two connector edits in requirements §10.3/§11.3 into registrations. Gives sign-up positions the same "badge or set" test for free. Fits the "native over config" rule: the audience editor looks the same everywhere.

### F4. A people-query layer that does not recurse in Ruby

**What.** `Team#all_descendant_ids` recurses in Ruby, one query per child (`team.rb:47-49`), and the HBR Pages repeat `Team.where(name:).flat_map { ... all_descendant_ids }` (`pages/team-roster.html.erb:18`, `safety-training-report.html.erb:15`). Requirements need a bounded query count for 200 people (requirements §11.6) and intake's approval page shows about 200 rows. Add `Team.subtree_ids(ids)` (a recursive query), `Person.on_teams(ids, managers:)` and `Person.visible_to(viewer)` as the only way new code asks these questions.

Size S. Generic; a good first upstream PR because it fixes a known performance gap (gp-map "Team recursion cost").

### F5. Person merge, earlier, with a registry

**What.** Merging two people is today a script (`~/dev/gatherpack-import/merge_person.rb`) run by Claude with an admin as actor. Intake keeps it for "Phase 6". Move it up, for two reasons: the kiosk creates people in a room with a manager typing, so duplicates become more likely than with the Google Form; and these specs add `person_id` to at least eight new tables (results, excuses, attestations, entries, household members, enrollments, applications' new columns, import rows).

The addition that makes it safe: `PersonMerge.register(table, column)` called by every feature that adds a person reference, plus a test that fails when a table with a `person_id` is in neither the registry nor a short exempt list. Without it, each new feature silently breaks the next merge. The screen is admin-only, previews what moves, and writes one audit entry.

Size M. Generic. **Touches.** Replaces the script; lets D2 offer "Merge" instead of "Link or keep separate". Also gives the "delete a spam person with their login" action in intake §11.5 the same registry for "has nothing else".

### F6. Encryption for new sensitive columns only

Intake adds the first `encrypts` (none exist today; `grep encrypts app` is empty) and so the first credentials. Use the opportunity once: add the keys, a short runbook (generate, store, rotate, what a lost key means for backups), and a rule that new columns holding personal data about minors use it. Do not encrypt existing columns: birthday is searched and ranked on (`person.rb:126-136`, ransackable attributes), and encrypting it breaks queries for little gain. Size S. Generic.

### F7/F8. Two small seams

Every feature in these specs edits `config/recurring.yml` and `config/routes.rb` (intake §17.3, requirements §11.3), and there is no seam for either (gp-map; `routes_proc` is commented out at `config/routes.rb:276`; `recurring.yml` holds two jobs). Add a loader for `config/recurring.d/*.yml` and enable `routes_proc`. For cards, do not edit `welcome/dashboard.html.erb` as intake §17.3 plans: register a section with `MyGatherpack.register_section` ([`my-gatherpack-spec.md`](my-gatherpack-spec.md) §6.1), so "Renew for 2028" and "Still to do" are sections. Size S for both. Generic, and each shrinks every later "Upstream files touched" table.

## 3. Data quality

### D1. A record-health set (the fix list)

**What.** The guardianship age limit only works when a birthday is on file: with none, a person counts as a minor or not by a global setting (`person.rb:134`, `Relationship.guardianship_ends_without_birthday?`). Intake treats unknown as "needs a guardian" (§7.4). So missing birthdays and missing guardian links decide who gets asked for what. Build this as an ordinary requirement set, "Record is complete", with existing kinds: `age` (not met "No birthday on file"), `has_login`, `person_field` (grad year), and `has_guardian` pulled out of "later" (requirements §1.2) into the first version. A manager gets a filtered list; each row's fix link goes to the field. No new mechanism.

Collect the missing facts where families are already working: the renewing confirm-your-information form asks for the birthday and for guardians, so the list drains by itself (the birthday field is family-level, `person_field.rb:57`). Size S. Generic. **Touches.** Unblocks a trustworthy `guardian_if_minor` signer (`form_access.rb:104-120`); gives guardian-only counts in intake a true denominator.

### D2. A duplicate queue, not just matching at verification

**What.** Intake matches only when an entry is verified (§6.3). Duplicates also come from staff entry, imports and old placeholders. Add a nightly job that fills a "Possible duplicates" list from the logic in `find_duplicate_people` (name, then login email), with Keep separate (remembered, so it is not asked again), Link, and Merge (needs F5). Also catches a student listed twice and the placeholder-then-real pair. Size M. Generic. **Touches.** Extends the existing MCP tool into a screen (parity both ways).

### D3. Guardian links as a renewal step

Under-age people with no guardian are the largest hidden gap. The renewal form includes "Who are your guardians?" so a family confirms or adds them, using intake's guardian-confirmation email (§6.2): a minor still cannot create a tie the guardian did not confirm. Emergency contacts are asked in the same step and stored with the weaker relationship of [BL-023](../backlog/BL-023-contact-relationships.md), which has no guardian powers. Size M, riding on the intake renewal path. Generic. **Touches.** Gives BL-022/BL-023 a first user, which is the case for finishing them.

### D4. List import: match, review, apply

**What.** The FIRST roster is synced by a local script that reads a PDF export (`~/dev/gatherpack-dev-data/first_roster/parse_first_roster.py`, `sync_first_roster.rb`) and grants badges. The same shape recurs: a training provider's completion list, a background-check list, a school's eligibility list, a sign-in sheet from an off-site event. Make that shape a native screen: paste or upload rows (name, optional email), see matched, ambiguous and unmatched, choose the person for ambiguous ones, pick the outcome (grant badge, set a field value, mark an attestation), apply, and keep the run (who, when, source) as an audit entry.

PDF parsing stays outside, as a small script that produces the same rows. The tool takes text. This respects the MCP boundary ([`mcp-expansion-spec.md`](mcp-expansion-spec.md) §3: no upload tools): the client may read a file and call the same apply action row by row, with the same checks.

Size M. Generic. **Retires** `sync_first_roster.rb` as the way to grant (intake §9.3 still says "synced by script"), `enrollment_read.rb` and `prod_friends_members.rb`-style one-off imports, and part of `register_placeholders.rb`.

## 4. Surfaces

### S1. "You still need" at the kiosk, from the checklist

**What.** [`kiosk-spec.md`](kiosk-spec.md) §7 plans a Reminders widget written as a Page script that re-implements FIRST, safety training, login and forms checks, and says in its own words that copying the Eligibility logic "would drift". Requirements make `Requirements.checklist_for(person)` (requirements §12) a cheap read of stored results. So replace the widget's logic with a native kiosk slot that lists a person's unmet items from it.

Rules: the kiosk is a shared screen. Each requirement gets a `show_on_kiosk` flag, default off. Items show as one short line with no numbers ("Safety training not done yet."). Managers see nothing, as in the widget spec. Only items with a thing the person can do next show a fix. Size S-M. The slot is generic; the widget itself stays fork-only (never upstream).

**Touches.** Replaces kiosk spec Phase 3b's content. If the requirements phase slips past January, ship the planned widget as a stopgap and replace it later (decision list).

### S2. One "your season" list on My GatherPack and the family page

Requirements §10.4 already adds a to-do section; intake §9.4 adds a household switcher and a renew card. These must be one component, not two: a card per person (the viewer and wards) with one ordered list that merges forms, sign-ups, unmet requirement items and the renewal step, and a single highlighted "Do this next". Guardian wording only when the viewer is a guardian. Size S (a section partial registered once). Generic. **Touches.** Fills the ward rows in my-gatherpack §7.2 with real content instead of per-feature rows.

### S3. A Season page for managers

**What.** A team page tab, "Season 2028", showing the funnel with counts and clickable lists: link opened, entries, verified, applied, approved, checklist met, renewed; and "who is blocking" (waiting for guardian, FIRST, forms, unverified email older than 3 days). Plus the actions that already exist, in one place: approve, nudge, send invite. It is a reading of data the specs already store, not new data. Size M. Generic.
**Touches.** Subsumes intake's "Waiting to finish" and "Haven't renewed" lists, and the requirements §10.4 "everyone with an open joining checklist" report, as filters of the same table.

### S4. One reminder per person per day

**What.** Three specs send reminders: intake §12 (3 and 10 days, renewal season), requirements open question 4 (met to not met), app-feel §8.8 (forms due, monthly commitments). Left alone, one family gets a separate email for each. Add a small collector: features register what a person still owes, and one job sends at most one "Still to do" email (and one phone notification, `PushTopics`) listing everything, with fix links, guardians getting their wards' items in the same message. The monthly-commitments job already works this way ("one email per person however many commitments they owe", app-feel §8.8); this generalizes it.

Add a "Message these people" button to any report row set ("people with the ticked status") that uses the same sender. Size M. Generic. **Touches.** Replaces the per-feature reminder jobs for new work; `forms-auto-reminders` and `commitment-monthly-reminders` become two sources of the same digest. Settings: one per set, off by default (rule 10).

### S5. A roster is a set with no requirements

The team-roster Page (`pages/team-roster.html.erb`, 82 lines: groups, contacts, print) and the "safety training with guardian contacts" Page need nothing a requirement set does not have: a population, columns, sort, filters, print. A set with zero requirements is a roster. Add an optional contact column that appears only where the viewer can already see the person's guardians (requirements §13.4 already specifies it). Size S on top of the report page. Generic. **Retires** `team-roster.html.erb`. Also fixes [BL-010](../backlog/BL-010-long-tick-box-lists.md) for printed lists by giving every list the same print rules.

### S6. Paper fallback for the open house

A printable one-page "Join" sheet with the registration's QR code and the short address, and a paper sign-in list that a volunteer types into the kiosk later. The kiosk fails when the Wi-Fi does, and a callout in a gym is the likeliest place. Size S. Generic. Cheap because the registration already has a slug and a title.

## 5. Retiring hand-built Pages and scripts

| Today | Becomes | By | Note |
|---|---|---|---|
| `pages/eligibility-report.html.erb` (700 lines) | Requirement set | Requirements phases 2-4 | Page stays as fallback for the first season (requirements decision 15) |
| `pages/attendance-report.html.erb` (218) | Attendance requirement drill-down | Requirements phase 1 | |
| `pages/safety-training-report.html.erb` (96) | Set with one badge requirement | Requirements phase 2 | Class sort stays a report option |
| `pages/outreach-report.html.erb` (200) | Outreach column and the commitment's page | Requirements phase 2 | |
| `pages/team-roster.html.erb` (82) | Roster set (S5) | After requirements phase 1 | |
| Kiosk Reminders widget (planned) | Native slot (S1) | With requirements | Do not build the Page script unless the stopgap is chosen |
| `pages/kickoff-countdown-widget.rb` | Reads Season named dates (F1b) | With seasons | Widget stays fork-only |
| `pages/scan-cards.html.erb` (180, Code 128 in ERB) | Stays a Page for now | | Issuing a scan token on approval becomes a placement outcome (below); printing stays |
| `pages/academic-eligibility.html.erb` (180) | Stays a Page | | A bulk editor of one field; requirements already say stay |
| `pages/clocked-in-report.html.erb` (176) | Stays a Page | | A live safety view, not a status |
| `sync_first_roster.rb`, `parse_first_roster.py` | List import (D4) plus the parser | D4 | |
| `assign_scan_tokens.rb` | Placement outcome "Issue a scan card" | Intake phase 1 | Token prefix and length become a setting; the model is `token.rb` as is |
| `rookie_badges_class_2030.rb`, `safety_badges_new_students.rb` | Placement rules and the F1 record | Intake phase 1 | |
| `merge_person.rb` | Person merge (F5) | F5 | |
| `enrollment_read.rb`, the enrollment CSV, the Google Form | Intake | After the first verified season | Intake Appendix A already keeps the form until then |
| `register_placeholders.rb`, `placeholders_to_teams_and_outreach_page.rb` | Duplicate queue (D2) and the claim-by-email match | D2 | |
| Per-season Page settings blocks (season badge names, teams) | Set configuration plus copy (F2) | | The "edit these at the top" habit ends |

Scripts that are about history (the Ditto and signup migrations, the concessions fixes) stay as records and are never re-run.

## 6. Things nobody is thinking about yet

### E1. Clearances that expire (adults)

**What.** Mentor background checks and youth-protection training lapse. A badge assignment has no date or expiry (`db/schema.rb:94-102`), so today a lapsed clearance looks identical to a current one, and the Page-only answer is a badge someone must remember to remove. Add a nullable `expires_on` to the assignment (a fork migration, additive; the assignment screen gains one optional date). The requirements `badge` kind gets "must not be expired on the window end or cutoff". The engine already has the hook for clock-driven change: `next_change_at` (requirements §6) makes the lapse appear on the day, and a "30 days before it lapses" digest item (S4) tells the adult and the person who verifies.

This keeps badges where they belong, as credentials with a date, not as status flags. The date is entered by whoever verifies (or by D4 from a provider's list), never by intake. Size M. Generic; the badge change is a plain upstream feature. **Touches.** Clarifies intake §9.3 ("Background checks and training: a badge-held check"); adds an upstream-table edit to list in `FORK.md` (the migration, plus a view for the date field).

### E2. Volunteer and mentor onboarding

Almost entirely configuration, as intake §1.2 says: a way to join with its own questions and a checklist that includes E1's clearance items and organizer-attested steps (an orientation held, references checked; requirements §6.5). The one addition: an organizer-attest list view ("tick who attended orientation") that attests many people at once, with no self-attest. Size S. Generic. Alumni and sponsors follow the same pattern (empty checklist).

### E3. Season close-out and alumni

**What.** Intake never removes anyone (decision 14) and shows "Haven't renewed". Someone must act. Provide a manager-initiated "Close out the season" screen: it lists non-renewers and the graduating class (from F1 and a grad-year field), shows what each action would do, and applies bulk moves: add to an alumni team, end membership in active teams, keep every record. Nothing happens on a schedule. Alumni are then a population (enrolled in a past season, not this one) usable for newsletters and invitations, and a "Stay connected" way to join exists for them (empty checklist).

Size M. Generic (the words "graduating" and "alumni" are team and field names an organization picks). **Depends on** F1 and F3.

### E4. Waitlist without touching upstream's enum

Intake §10.6 adds an application status (`status: 3`) to upstream's enum. Simpler: a nullable `waitlisted_at` column on the application, a cap on the way to join counted from placed memberships, and "Promote" as a manager action; an optional hold ("offered, 48 hours to confirm") using the notices that exist. No enum edit, nothing in upstream's policy changes. Before building, check whether sign-up slots (`signup_slot.rb` capacity) already imply a waiting list that should share the promote logic. Size S-M. Generic.

### E5. Trip rosters from eligibility

**What.** The reason BL-003 existed: a decided list of who can travel. With requirements, a trip is a sign-up sheet whose positions require a set (requirements §10.3, `-signups` connector) plus a cutoff date; the set nests the season set and adds travel documents. Pull "Record this list" (requirements §9.4, marked later) into the first season: a snapshot of names, statuses and configuration, read-only, printable, with who recorded it and when. It is the answer to "why was this student on the bus".

Add to the snapshot a roster print with guardians' phone numbers and the E8 emergency data, visible only to the trip's organizers. Size M. Generic. **Touches.** Closes BL-003 as superseded (requirements already says so) and changes requirements open question 5 to "yes, in the first version". Also lets the sign-up page say why someone cannot take a seat using the failing item's fix link instead of "Needs the X badge" (signups-spec §3.3), and retires the "a form grants a badge and the position requires the badge" workaround stated there.

### E6. Participation statements and awards

**What.** Students ask for a letter of hours and years of service for schools and scholarships, and teams give awards from thresholds. With F1 (years on the team) and the time clock and commitments (hours by season), a "Statement of participation" page is a read of existing data: seasons, teams, hours by season, signed by a named role. A set with an `hours` or `commitment_met` requirement and "Record this list" is the awards list. Size S-M. Generic. Do not build a certificate designer: a clean print page and CSV.

### E7. Dues, fees and waivers

**What.** Intake lists dues as a non-goal (§1.2), requirements defers `ledger_balance`. A Stripe payment gateway exists (`app/models/gateway/stripe_gateway.rb:2`, `LedgerPayment`) and the orders spec has funding sources, so a fee on a way to join could eventually be paid in the app. Start smaller: dues are a `commitment_met` in dollars or an organizer-attested item ticked by the treasurer role; a waiver is an excuse (requirements §7) whose reason is visible only to a finance badge, not to every organizer of the set. That needs one extension to requirements: a per-requirement "who can read excuse reasons". Size S now; L for in-app payment later. Generic.
**Touches.** [BL-011](../backlog/BL-011-accounting-integration.md) (accounting integration) decides the books; this should not pick a side. Keep payments out of 2027 registration unless the owner says otherwise.

### E8. Medical and emergency information at events

**What.** Families sign medical releases and list contacts, then the leader at an away event needs them on a phone or on paper. Person fields have read levels and forms hold signatures, but nothing assembles a roster with allergies, contacts and consent status for one event. Add an "Event safety sheet" for an event or sign-up sheet roster: attendee, the medical and dietary fields, emergency contacts (BL-023), guardians' phones, and whether the required forms are met. It is visible only to the event's organizers and named chaperones, only from a day before to a day after, printable, and every opening is logged.

The log is new: PaperTrail records writes, not reads (gp-map). A small access log table (who opened which sheet, when) is part of the item. Size M. Generic. **Depends on** person fields, forms, requirements, BL-023.

### E9. Retention and season archiving

**What.** These specs collect more data about minors than GatherPack has held, and nothing in them says how long it is kept beyond unverified entries (7 days, intake §11.5). Needed: a written policy first (decision list), then code to apply it with a preview: archive a Season (read-only, lists recorded, live stored results reduced to the overall), a report of denied applications older than N months, and an "inactive people" report (not enrolled in the last two seasons) with a one-click purge of medical and emergency data, never of the person or their history. Nothing runs by itself. Size M-L. Generic.

### E10. Season statistics for sponsors, schools and the registering body

**What.** Counts the same people ask each year: participants by class and by new or returning, hours, outreach events and hours, number of mentors, retention from last season. All derive from F1, commitments and the time clock. Provide one "Season report" page with counts only, cells under 5 suppressed, CSV export, and no names. A separate, opt-in public page is a decision, not a default. Size M. Generic.

### E11. Interests as "any of" in placement

A way to join can ask which sub-teams a student is interested in ("Choose any that apply") and a placement condition "answer includes" can add them to those teams. Several picks mean "any of" in the model (standing preference). Size S, an addition to intake's condition kinds (§8). Generic.

### E12. Language

Public registration serves families that may not read English at home. Allow the registration's texts and the notices to be overridden per language, chosen from a link or the browser setting. Size S-M. Generic. Ask the product owner whether this is needed before spending anything.

### E13. Send invites from the report

The `has_login` requirement's fix text is "ask a leader to invite you". Give leaders a button on the report to send the invitation email that intake already builds for kiosk entries (§7.2). It closes the "new people get logins" step for anyone who joined outside intake. Size S. Generic.

## 7. MCP at parity

Tools allow exactly what the app allows. Existing proposals: intake §15, requirements §11.4. Gaps these improvements add (each rides with its branch):

| Tool | App equivalent | Branch |
|---|---|---|
| `list_seasons`, `get_season` | Season screens | `feature/mcp-seasons` |
| `copy_registration`, `copy_requirement_set` | The Copy buttons; create drafts only | with each connector |
| `season_enrollments` (by person or team) | F1 views | seasons |
| `people_meeting` (a set and a status, names within the caller's view) | Report filter | `mcp-requirements` |
| `list_possible_duplicates`, `resolve_duplicate` (admin) | D2 | `mcp` |
| `badge_expiries` | E1 list | `mcp` |
| `message_people` (the S4 sender, a set and a status) | The button | `mcp` |
| `record_list` | Record this list | `mcp-requirements` |

Not exposed: merge (admin screen only, as deletion is, expansion §3), the access log, the safety sheet content (nothing in an AI client log), the import apply (rows may be sent one at a time with the app's checks, but no bulk tool), retention purges.

## 8. Risks and cross-cutting concerns

**Public pages (intake §11 covers the controls).** Additions: the "Message these people" sender and the S6 QR sheet put a registration address in print, so a leaked slug must not reveal anything (a closed registration already answers like an unknown one). The optional public statistics page (E10) needs small-cell suppression before it exists. The safety sheet (E8) is the highest-value page in the app for an attacker, so it is never indexed, never cached by the service worker ([`app-feel-spec.md`](app-feel-spec.md) §7.2: check the cache rules), and logged on open.

**Stored results and write storms.** Requirements invalidate by change (§8.2). Bulk actions here touch hundreds of people at once: approving a class, the season rollover, a roster import (D4), a class-team move. Each would queue refreshes for every set. Give bulk operations a way to say "pause refreshes, then queue one per set when finished" (the refresh table already coalesces by set and person). Test it with the 150-person case.

**A feedback loop between the two specs.** Intake approval creates a membership, which invalidates results, whose status change fires `requirement_status_changed.gatherpack`, which intake listens to. Intake's handler must be idempotent (approving an approved application is a no-op) and must run in the refresh job, never inside a user's save. Write that into the intake handler's test list.

**Rows for people who may never exist.** Kiosk entries create people at once, marked unverified; requirements create results for them (applicants are a population). An expired or deleted person must take their results, attestations and entries with them, and a merge must move them (F5). One test per table, driven by the F5 registry.

**Configuration sprawl.** After these specs, one season has a registration, ways to join, placement rules, a joining set, an eligibility set, forms, commitments, sign-up sheets and widgets. Rules to keep it small: one set per purpose and per season; names contain the year; F2 lists everything for a season on one screen; an unused draft older than 60 days is flagged on the Season page; every kind and way to join shows "Setup problems" the way requirements §13.3 does. The risk is not the engine, it is a coordinator facing fifteen screens in May.

**Badges as status flags.** The season sync badges (`2027 FIRST Registered`) are facts written by a script and read by the `badge` kind; that is fine. What must not return is a badge kept in step with a computed answer (BL-003). F1 and E1 give the two facts that tempted badges (was here in 2027; clearance valid until X) a proper home.

**Upstream acceptance.** Seasons, requirements and intake are a large surface for one maintainer, and the audit disclosure has had no reply since 2026-11-04. Slice the PRs so each stands alone and is useful: seams (F7), query helpers (F4), Season, requirements core, then each kind connector. Send nothing until upstream has caught up with what is already with them; keep the branches ready. Written to upstream's standards from the first commit, as the rules require.

**Performance and cost of the first load.** A first view of a set computes one person's results (requirements §8.2); a manager opening a 300-row page with empty results must not trigger 300 of those. The first compute is a job, with "Computing..." until done.

## 9. Suggested sequence

Assumptions to confirm: today is 2026-11-05; build season starts 2027-01-07; the next season's Season runs 2027-05-01 to 2028-04-30 (as in intake Appendix A); an open house or callout happens in April-May 2027 and registration opens on May 1; FIRST registration for the new team happens in late summer, which makes the renewal checklist due by about September; the first away event is in late February or March (ask for the date). A release freeze runs from about 2026-12-20 to the end of the first competition weekend except fixes, so nothing new reaches production while the team is building.

| When | Do | Why then |
|---|---|---|
| Nov 5-30, 2026 | Requirements phase 1 on Ditto (their plan). F0 split, F7/F8 seams, F4 queries, F6 keys. Decide the open items below | Seams and queries are small, upstreamable and shrink the other branches. Nothing here touches production |
| Dec 2026 | Requirements phases 2-3. `feature/seasons` with named dates (F1b). D1 as a set (birthdays and guardian links), so the confirm form can collect them in spring. Decide the kiosk stopgap | D1 is configuration once sets exist. A stopgap widget only if phase 4 will slip |
| Before Jan 7, 2027 | Requirements phase 4: release, Page stays as fallback. S1 slot if ready, else stopgap widget | The team is watching eligibility from the first meeting |
| Jan-Feb 2027 | Build season: fixes only in production. On Ditto: F3 population layer, F1 enrollment record plus backfill, F5 person merge, E5 "Record this list" and the trip sheet, E1 expiring clearances | These are the pieces the spring registration stands on, and the away events need E5 and E8 |
| March 2027 | Intake phases 1-2 on Ditto (core, seasons-forms, renewals). E8 safety sheet. D4 list import (FIRST roster) | E8 before the first away event if it falls here; intake checked with real data before April |
| April 2027 | Intake phase 4 (kiosk) and S6 paper fallback. F2 assistant used to create the 2028 registration and sets as drafts. Dry run at a team meeting | The callout is the kiosk's first real use |
| May 1, 2027 | Registration opens. Google Form retired once the first entries verify. Renewals open for returning members | Matches the Season dates |
| May-Aug 2027 | S4 reminders, S3 Season page, D2 duplicate queue, E13 invites. Waitlist (E4) only if a cap is needed | The weeks when families act |
| After the first competition season ends | E3 close-out and alumni, E10 statistics, E6 letters | Needs a full season of F1 data |
| Fall 2027 | E9 retention, E7 payments if wanted, E12 language if asked | Policy before data piles up |

## 10. Decisions for the product owner

1. **Season enrollment as a record.** Should "was on the team for a season" and "renewed" be a stored row (recommended) rather than a season badge as intake's default has it?
2. **Named dates on a Season.** OK to put labelled dates (kickoff, dues deadline, first away event) on the Season so widgets and due dates read them?
3. **Expiry on badge assignments.** OK to add an optional expiry date to badge assignments (a small addition to an upstream table) so adult clearances can lapse on a known day?
4. **Kiosk and a shared screen.** May the kiosk show "you still need X" lines after a scan (labels only, no numbers, off per requirement by default), and should the planned Reminders widget be shipped now as a stopgap or skipped?
5. **One reminder per person.** One combined "Still to do" email and push per person per day, rather than one per feature? Should a status change from met to not met send anything by default (requirements open question 4)?
6. **Dues in 2027.** Treasurer-attested or commitment in dollars through the season, with in-app payment later (recommended), or in-app payment at launch? Who may read a waiver's reason?
7. **Event safety sheet.** Who may open it (event organizers and named chaperones), for what window (a day before to a day after), and should every opening be logged?
8. **Retention.** How long to keep denied applications, medical and emergency data of people not enrolled in two seasons, and former members' records?
9. **Pull person merge forward** to before the kiosk ships, with the registry rule that every new table registers its person columns?
10. **Release freeze.** Freeze production releases from about Dec 20 to the end of the first competition weekend, fixes only?
11. **Dates.** Confirm: registration opens May 1, 2027; an April open house; first away event date; and whether "Record this list" ships in the first requirements release (requirements open question 5).
12. **Alumni.** Should season close-out offer to move graduating students and non-returners to an alumni team with a stay-connected way to join, always by a manager's action?
13. **Statistics.** Are season counts for sponsors and schools private (an export a manager makes) or may an aggregate public page exist?
14. **Upstream order.** Offer seams and query helpers first as small pull requests once upstream has caught up, keeping Seasons, Requirements and Intake local until then?

## Appendix: HBR-only facts

Kept here so the sections above stay generic.

- Class teams (`Team 1747 - Class of 20NN`) are rolled over by hand each year; F2 creates the new freshman team as a step, and D1/placement use the grad-year field.
- The FIRST roster arrives as a PDF export; the parser stays a local script that produces rows for D4. The two season badges (`2027 FIRST Registered`, `2027 FIRST Consent Signed`) remain facts the `badge` kind reads.
- Scan cards are `1747` plus eight digits; placement issues one at approval, using a setting for the prefix. The print Page stays.
- Dues are recorded outside GatherPack (Zeffy); until the books decision (BL-011), treasurer attestation credits them.
- The Eligibility Report, safety training, outreach, team roster and attendance Pages retire in the order in section 5. Academic eligibility and Who's Clocked In remain Pages.
- Mentor clearances (background check, youth-protection training) become E1 sets for the adult team; the safety training badge for students stays as is.
- Spanish or other languages (E12): unknown need; ask the team before building.
