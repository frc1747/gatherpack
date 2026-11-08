# Spec: Checklists

Status: rev. 3, 2026-11-06. Not built. Code facts checked against integration `49609326`. Decisions are in §15. Companion: `membership-intake-spec.md` (what it needs from this is §13).

Rev. 3: one feature. "Requirements" and "Commitments" become **Checklists**; a commitment is a **count item** inside a checklist, on its existing tables (§6.2, §11). Rev. 2 kept: no seasons, every date is configuration (including "within the last N"), form expiry honoured.

Supersedes [BL-003](../backlog/BL-003-attendance-eligibility-badge.md) (a badge kept in step with attendance). Supersedes the user-facing parts of [`signups-spec.md`](signups-spec.md) §4 (Commitments); that section is left as written and still describes the engine behind count items. Does not depend on [BL-002](../backlog/BL-002-period-hours-date-bounds.md); the attendance item reads meetings itself (§6.3).

## 1. Goal

Organizers say what a person must have, do or be, and GatherPack answers for every person in words: **done**, **almost** (planned, not yet done), **not yet**, or **not counted**, with why and how to fix it. Some items are conditions (holds a badge, form signed, field is Yes). Some are counts (three shifts, one outreach event, pooled by family). Both sit in one list and give one answer. The answer shows in a report, on the profile, on a person's own to-do page, in hooks, and as a test other features can use ("only people who finish this").

The test is whether an organizer can rebuild today's Eligibility Report (about 700 lines of admin-written ERB) with screens only, and whether next year's copy takes minutes. §14 does this on paper.

### 1.1 Non-goals

- A programming or formula language for organizers (§3).
- Scoring, ranking or points.
- Writing the answer back as a badge. A badge as a status flag goes stale (BL-003); the stored result is the alternative (§8).
- Names for HBR's policies in code. "Students", "travel", "concessions" appear only in §14, as configuration.
- A season, year or period concept. Dates are enough (§9).

### 1.2 Use cases

| Use case | Verdict | How |
|---|---|---|
| Eligibility over a span of dates: attendance share by month, registration, a roster badge, a signed form, a field, a quota | Fits | One checklist, one item each (§14) |
| Every Commitments use case in `signups-spec.md` §1.2 (shifts, ratios, caps, household quotas, potluck quantities, quotas met by check-ins) | Fits | Count items, unchanged engine (§6.2) |
| Pre-trip decision on a date, so it doesn't swing | Fits | Cutoff date on the checklist (§9.2) |
| A manager excuses a missed meeting or waives an item for one person (rare) | Fits | Excuses, managers and admins only (§7) |
| Give or take credit on a count by hand | Fits | Adjustments (§7) |
| Joining checklist for a new member, including applicants not yet on a team | Fits | Applicants population, dated `form_complete`, `has_login` (§13) |
| "Missing safety training, with guardian contacts" | Fits | Filter "Not yet", optional contacts column (§14.4) |
| Position or form open only to people who finish a checklist | Additive | Predicate (§10.3); small change in each of those branches |
| Dues or ledger balance not negative | Additive, later | `ledger_balance` kind |
| Hours worked in a window | Additive, later | `hours` kind |
| "Has a guardian on file with an email" | Additive, later | `has_guardian` kind |
| Recently active (check-in or punch in the last N days) | Additive, later | `recent_activity` kind |
| "Can still reach the minimum" projection | Additive, later | Option on `attendance` |
| Record the list as decided for a trip | Fits | "Record this list" (§9.4) |
| Any-of across different data ("badge OR form") | Fits | `any_of` group (§5.3) |
| Arbitrary formulas over several attributes | Non-goal | Add a kind instead (§3) |
| Live "who is clocked in" page | Non-goal | Stays a Page; it isn't a status |
| Bulk editing a person field | Non-goal | Stays a Page; the checklist only reads the field |

## 2. How it works today

- **The report is a Page.** `pages/eligibility-report.html.erb` computes everything in one ERB: attendance rules by month with pools and weekly checks (lines 146–200), concessions with family pooling (217–260), outreach and rookies (261–277), FIRST badges (304–318), an academic field (319–322), the overall rule (324–345), labels and filters (356–420), viewer tiers (lines 100–112). Pages run with `ERB.new(...).result(binding)`; only admins author them.
- **It already prefers Commitments.** When the two commitment titles exist it calls `commitment.progress(people)` instead of its own tallies. That call stays valid after this change (§11).
- **Two features, one question.** Commitments answers "has this person or their family done N of X". The Page answers everything else by hand. People read both as one answer ("am I eligible"), so it is one feature.
- **Commitments, as built** (`feature_commitments`, live):
  - Credit source kinds in a registry (`Commitments.register_source`, `commitments.rb:38`; `SourceKind`), each with batch `records(person_ids)`; planned vs confirmed records, a ratio and cap per source (`commitment_source.rb:50-57`), dedupe per worker and event (`commitments.rb:60`, `progress.rb` dedupe winners).
  - Population = owing team + owing badge − exempt badge (`commitment.rb:170-175`); `counts_when` confirmed or planned; groups by relationship with base plus additional per member and relatives' credit (`commitment.rb:213-230`); period `starts_on`/`ends_on` (`commitment.rb:51-52`).
  - Batch API `commitment.progress(people)` (`commitment.rb:188`) returning `Progress` (owed, confirmed, planned, remaining, met?, lines).
  - Adjustments with a reason; no self- or relative-approval, group-wide (`commitment_adjustment_policy.rb`, `commitment.rb:154-165`).
  - Organizers by badge grant (`commitments_organizers`, `commitment.rb:76-116`).
  - Visibility by `PersonCommitmentsPolicy`: the person sees what they owe and what a group they're related to owes; others only what they run or what is grouped through their relationship.
  - Surfaces: sidebar item (`features.rb:195-202`), pages under `/commitments`, `/people/:id/commitments` (`routes.rb:192-198`), a profile tab (`commitments_profile_tab.rb`), the dashboard card "My Sign-ups and Commitments" (`SignupsSummary`), the sign-up dialog hint (`Commitments::SignupHint`), MCP `list_commitments`, `commitment_progress`, `add_commitment_adjustment`, `remove_commitment_adjustment`.
- **No season, and none needed.** No `Season` class or `season` column exists (`db/schema.rb`). Time clock periods have date columns (`schema.rb:1116`) and events link to a period (`events.time_clock_period_id`, `schema.rb:275`).
- **Audience levels** (`audience_levels.rb`) and `AudienceAccess` answer "subject, guardian, leader, teammate"; form badge grants (`form_badge_grant.rb`) let admin-assigned badges widen access.
- **Hooks fire inside the save** and `Hook#run` doesn't rescue (`hook.rb:47`); hooks for a derived status must fire from a job (§8.3).
- **Predicates are closed.** Sign-up position rules are an enum of three kinds (`signup_position_rule.rb:19`); form audience rules are team, badge or person (`form_audience_rule.rb:16`).

## 3. Options for flexibility

| Option | Why it fails here |
|---|---|
| A. Expression language or Ruby | Only admins could write it. No live "who passes" until it runs. Can't be explained to a parent in words. The app already has `eval` in Pages, hooks and reports; the security audit (80 findings) is a reason to add no more. |
| B. Generic attribute / operator / value builder | The attributes aren't columns. Attendance share needs meeting overlap and weekly checks; a family's shifts need pooling; "signed up but not done" is a third state. A generic builder hands people primitives to assemble. |
| **C. Typed item kinds, each with a small fixed form** | Each kind knows its data, its missing-data case, its explanation and its fix link. Previewable and explainable. A new need is a new kind, a small additive change in a connector branch. |
| D. Presets | A way to use an engine, not an engine. |

**Recommendation: C, with D on top** (copy to next year, §9.3, and sample checklists). B survives only inside kinds, where operators are fixed by data type. Count items are one more typed kind: the form is a unit, an amount, what counts, and optional pooling; nothing else.

- **Combination.** A checklist is "all of" its items. `any_of` groups items, groups can hold groups, and a checklist can require another (§5.3). Only cycles are refused. No NOT, no precedence.
- **Parameters.** A kind's form is a handful of fields. Dates default to the checklist's window (§5.2).
- **Exceptions.** An item says who it doesn't apply to (§5.2); a manager can excuse a person (§7).

## 4. Concepts and names

| Concept | Meaning |
|---|---|
| Checklist | A named list of items for a population over a window of dates ("2026-27 Eligibility", "Concessions"). Belongs to a team. Has organizers. |
| Population | Who it covers: rules to include or exclude a team, badge, person, or applicants to a team (§5.1). |
| Item | One line on the checklist. Two families: **condition items** (badge, form, field, attendance, login, team, age, attested, another checklist, any-of) and **count items** (do N of something, with credit sources and optional pooling). |
| Count item | The former commitment: an amount in a unit, credit sources with ratio and cap, planned vs confirmed, optional family pooling, adjustments (§6.2). |
| Result | The stored answer for one person and one item: status, summary, detail, numbers. One more row per person for the checklist's overall. |
| Status | `met`, `pending`, `not_met`, `exempt`. Default words: Done, Almost, Not yet, Not counted (HBR sets Eligible, Pending, Not eligible). Labels such as "Rookie" or "Excused" ride on `exempt`. |
| Overall | Any counting item `not_met` → not met; else any `pending` → pending; else met. `exempt` is ignored. |
| Excuse | A manager's or admin's reasoned exception for one person on an item or one meeting (§7). |
| Adjustment | Credit given or taken on a count item, with a reason (§7). |
| Grant | Lets holders of a badge, or members of a team, see a checklist's overall and chosen items for everyone it covers (§10.2). |
| Attestation | A recorded "this is done" by the person, a guardian, or a manager (§6.7). |
| Window | The checklist's dates. An item's dates default to it and can be overridden. |

**Names.**

| User sees | Code (new) | Code (kept as is) |
|---|---|---|
| Checklist | `Checklist`, `checklists`, neat id `chkl_` | |
| Item | `ChecklistItem`, `checklist_items`, `chli_` | |
| Count item | `ChecklistItem` with kind `count` | `Commitment` (and `commitments` table, `cmt_`) |
| What counts (credit sources) | | `CommitmentSource`, `Commitments::SourceKind`, `Commitments.register_source` |
| Give or take credit | | `CommitmentAdjustment` |
| Who it covers | `ChecklistRule` | `Commitment#owing_*` columns (legacy, ignored when linked) |
| Done / Almost / Not yet | status `met` / `pending` / `not_met` | |
| Excuse | `ChecklistExcuse` | |
| Checklists feature / switch | `feature_checklists` | `feature_commitments` (treated as on, §11.3) |
| Checklist organizers setting | `checklists_organizers` | `commitments_organizers` (read through, §11.3) |

Users never see the word "commitment"; a count item is "Count" (Decision 24).

## 5. Model

### 5.1 Checklist and population

A checklist has: `team` (the reach, and who may run it), `title`, `description`, `starts_on`/`ends_on` (a window; each end is a date or relative, §9.1), optional `cutoff_on` (§9.2), `status` (`draft`, `active`, `archived`), overall words, `read_level` (an `AudienceLevels` level, default `family`: the person, their guardians and their leaders), `created_by`.

**Population rules** reuse `FormAudienceRule`'s shape: include or exclude a team (with or without managers), a badge's holders, or one person. One new target type, **applicants**: people with a pending `MembershipApplication` (`schema.rb:595`) to a team. Computed whenever needed, so people who join later are covered. The population must be within the checklist's team and below, except applicants, who are within the team they applied to. Rules live in `checklist_rules` (checklist-level when `item_id` is null).

### 5.2 Item

Fields: `kind`, `config` (jsonb, validated by the kind), `label`, `position`, `counts` (true: affects overall; false: shown only), optional `starts_on`/`ends_on` overriding the window (**every kind that looks at time reads these**; §6.1), optional `due_on` (when not done after this date, the label reads "Missed"), `read_level` (§10.1), `exempt_label`, `parent_id` (inside an `any_of`).

**Applies to.** The same rule table with `item_id` set: rules narrow who the item covers (include) or exclude people. Someone outside gets `exempt` with `exempt_label` ("Rookie"). For a count item this is who owes it: the narrowed-out are "Doesn't owe", and the pooling rules (§6.2) treat them as relatives, as Commitments does today.

### 5.3 Combining

- A checklist's items are "all of": every counting item must be met.
- **`any_of`** holds child items. Met when any child is met; else pending when any child is pending; else not met; the result says which passed. A child can be an `any_of` or any other kind, to any depth. The editor draws each group as a box headed "Any one of these is enough"; nested boxes indent.
- **`checklist`** is a kind pointing at another checklist: met when the person finishes it (or isn't covered, `exempt`). No depth limit.
- A count item can sit inside an `any_of` ("3 shifts, or the buy-out form").
- UI rule: several picks on one screen mean "any of", and the screen says so ("Any of: [badge] [badge]"). A kind whose picks are "all of" says "All of".

**Limit kept: no cycles.** A checklist that requires itself, directly or through others, never settles; checked on save by walking the references. No depth or size cap: a nested checklist is read from its own stored results (§8), so cost doesn't grow with depth, and the editor draws nesting recursively. Deliberately absent: NOT and expressions (a "not" is an exclusion rule, §5.2).

### 5.4 Result and status

`checklist_results`: `item_id` (null = overall), `checklist_id`, `person_id`, `status`, `summary` ("2 of 3 shifts"), `detail` (full explanation), `measures` (jsonb: `meetings`, `percent`, `confirmed`, `planned`, `owed`, …), `fix` (jsonb: `{label, path, action}`), `excuse` (jsonb: `{by, at, expires_on}` when excused), `previous_status`, `changed_at`, `computed_at`, `stale`.

Missing data never silently passes. Each kind says what missing means (default **not met**, with the reason: "No birthday on file"). Where blank is a real value the kind offers "Blank counts as…". Nothing to judge yet returns `exempt` with a label ("No meetings yet"), or `pending` under a minimum (§9.5).

## 6. Items

A kind is a class registered with `Checklists.register_item_kind(:badge, Checklists::Kinds::Badge)`, the same shape as `Commitments.register_source`. Interface (`Checklists::ItemKind`):

```
self.label / self.settings          # editor fields (badges, teams, field, form, number, date, choice, rules table)
self.problems(config)               # deleted badge, missing field... shown to organizers
evaluate(people, context)           # BATCH: { person_id => Result }; context: window, as_of, cutoff, checklist
explain(result)                     # the plain-words sentence (stored as detail)
self.invalidations                  # which records, when changed, make which people stale (§8.2)
self.next_change_at(config, ctx)    # next moment the answer can change with no data change
self.measures                       # named numbers: label, type, owner_only?
```

Evaluation reads data directly, without the viewer's permissions; **visibility is enforced when results are shown (§10)**, never inside a kind.

### 6.1 Kinds

| Kind | Family | Branch | Settings | Done / almost / not yet | Missing data |
|---|---|---|---|---|---|
| `count` | Count | `-count` | Unit, amount, additional per group member, what counts (sources), pooling relationship, counts when (§6.2) | Done: `Progress#met?`. Almost: confirmed + planned reaches the amount (when counting confirmed only). Not yet: otherwise. | Doesn't owe → exempt |
| `attendance` | Condition | `-attendance` | Rules table, extra hours count, leeway, judge after N meetings (per rule), optional periods (§6.3) | All rule groups pass | No meetings yet → exempt "No meetings yet" |
| `badge` | Condition | core | Badges, any of; optional "assigned on or after" | Holds any (assigned in the dates, if asked) | Deleted badge → problem shown, not yet |
| `team_member` | Condition | core | Teams, any of (and below); optional "joined on or after" | In any | |
| `has_login` | Condition | core | | A `User` with an email | No user → not yet |
| `age` | Condition | core | Min and/or max; on a chosen date (default the window's end) | In range | No birthday → not yet "No birthday on file"; shows pass/fail, never the date |
| `person_field` | Condition | `-person-fields` | A field; operator by type (is any of, is not, on or after, at least, is filled in); "blank counts as"; optional "last changed on or after" | Per operator | Blank → by "blank counts as" (default not yet) |
| `form_complete` | Condition | `-forms` | Forms (all of); signed in a date window (§6.4), or "ever" | Reads the response status (§6.4) | Outside the form's audience → not yet, with a problem listed (§6.4) |
| `attested` | Condition | core | A statement; who attests (the person, a guardian or the person, a manager); optional "on or after" | Attested in the dates | |
| `checklist` | Condition | core | Another checklist | Its overall | Not covered → exempt |
| `any_of` | Condition | core | Child items | §5.3 | |

Later (§1.2): `ledger_balance`, `hours`, `has_guardian`, `recent_activity`. Check-ins at an event type are not a separate condition kind: a count item of 1 does it, so there is one way to count activity.

**Dates on every kind that looks at time.** Each such kind has a date field defaulting to the checklist's window and overridable per item. `count` reads its own period, which is the item's dates (§6.2). Because the date is on the item, one badge or form can serve several checklists with different windows, and a copy only changes dates.

### 6.2 Count items

A count item is the existing Commitments engine behind a new form. Nothing in how credit is counted changes:

- **What counts.** Credit sources in order (`CommitmentSource`): check-ins at an event type, sign-ups to a sheet or position, and any kind a connector registers with `Commitments.register_source`. Each has a ratio ("3 count as 1") and an optional cap per person. Events must be held by the checklist's team or below, within the item's dates.
- **Planned vs confirmed.** A check-in at an event not yet started, or a sign-up not yet fulfilled, is planned. "Counts when" picks what completes the item: confirmed only (planned shows as Almost) or planned too.
- **Dedupe.** One worker at one event counts once, across sources; a record made on someone's behalf wins; two people working for the same person count twice (`progress.rb` dedupe winners). Unchanged.
- **Pooling.** With a relationship type chosen, people related through it owe together: the amount for the first member plus an additional amount for each other. Credit of relatives outside the covered people (a parent working a shift) counts for the group; a half-sibling chain joins groups; two people who don't owe never link (`commitment.rb:205-230`). Without one, each person owes alone. "Couples = 2 shifts" is two sign-ups.
- **Who owes.** The checklist's population, narrowed by the item's rules (§5.2). Owing replaces the commitment's own owing team, owing badge and exempt badge; for a linked commitment `owing_people` reads the item (§11.2).
- **Dates.** The item's dates are the commitment's period. Relative dates (§9.1) are resolved into the commitment's `starts_on`/`ends_on` at each refresh. A cutoff on the checklist shortens the period to the cutoff.
- **Result.** Summary "2 of 3 shifts"; detail with the breakdown per source and the group's members; measures `confirmed`, `planned`, `owed`, `remaining`. The pooled family is one number shown to each member.
- **Sign-up hint.** In the sign-up dialog: "2 shifts left on Concessions (Eligibility)" — one line per item this place counts toward, shown only to viewers who may see that item for the person (§10.1).
- **How to earn.** The item's page lists each source's `how_to_earn` line and upcoming events, as the commitment page does now.

### 6.3 Attendance

Takes the report's logic unchanged, made batch and testable:

- **Meetings** are events linked to a time clock period that start within the rule's dates and have ended (`end_time < now`, or `<=` the cutoff). The kind queries events itself with day bounds in `Time.zone`, so BL-002's date bug doesn't touch it. By default every period overlapping the item's dates is used; the item may name periods to narrow it.
- **Credit** is only punched time overlapping a meeting (merged intervals); leaving early costs, staying late adds nothing. `extra_hours_count` lets extra time make up missed time within the same group, never above 100%.
- **Rules** are rows: name, dates (the screen offers "every May–Aug" shortcuts that fill in dates), share of meeting hours, `weekly` (every week passes separately), and carry-over: each rule is **judged on its own** or **counted together with** named others (a pool). Nothing is built in: the screen says which it is ("Judged on its own" / "Counted together with: Summer").
- **Measures:** `meetings` attended of held, `credited` hours, `percent`, `extra` (owner-only).
- **Leeway** in minutes (default 1, matching the Page's one-second tolerance), so parity is exact.
- **Excused meetings.** A manager or admin can excuse a person from one meeting (§7); it leaves their required and credited hours.

### 6.4 Form items, dates and expiry

`form_complete` reads the response's status, not `activated_at` alone:

- **Done:** `complete?` and the active submission's `activated_at` is in the item's date window ("on or after <date>" or "within the last N days/months", default the window's start).
- **Almost:** a newer draft or pending submission is open, or a signer is awaited ("Waiting for <guardian>'s signature").
- **Not yet, needs a guardian:** the form has a guardian signature (`FormAccess.signer_roles`) and the person has no guardian at all (`Person#guardians` empty). Detail "Needs a guardian linked", fix: add a guardian (the person's relationships page, for a viewer who may edit them). Nothing is in motion, so this is Not yet, not Almost. No separate `has_guardian` kind is needed for this; the later one in §1.2 stays for checks outside forms.
- **Not yet, not asked:** the person is outside the form's audience. Detail "This form isn't asking them; add them to its audience", fix: the form's audience screen for a viewer who may edit it. The cleaner fix is the form audience target `checklist` (§10.3), "everyone this checklist covers". It is never `exempt`, because exempt would pass silently; it is also listed in problems (§6.5).
- **Not yet:** no response; `needs_reconfirmation` (including the expired reason from intake §7.5); or signed before the window.
- **Detail:** "Good until <date>" when `FormResponse#expires_at` is set; "Expired <date>" when expiry is why it isn't done, with the form as the fix.
- **Cache:** listens to `form_responses - incomplete` and the other form status events; `next_change_at` is the earliest upcoming `expires_at`, so an expired item never stays Done.

**Signing again needs no forms change.** `FormResponsesController#update` calls `start_submission!` (`form_responses_controller.rb:28`), which starts a new draft from the active answers and gets a new `activated_at` on submit. A form can be answered only while open (`form_access.rb:72`). If the form page doesn't offer a new version on an already complete response, that is the one forms change, made in `feature/forms` and agreed with intake.

**Form expiry or the item's date?** Use the **form's expiry** when the rule belongs to the form everywhere ("the media release is good for a year", wherever it's asked). Use the **item's date** when it's one checklist's rule ("signed since Sept 1 for this trip").

### 6.5 Problems list

Each kind's `problems` shows on the checklist page to organizers, and as a count on the checklists list. Besides deleted references, `form_complete` reports: a form that is **closed or still a draft** ("nobody can sign it"); a form whose **`closes_at`** (`schema.rb:420`) falls inside the item's window ("closes <date>"); and **covered people outside the form's audience** ("12 people covered here aren't asked <form>; add the checklist to its audience"). An item with a problem still evaluates, so nobody passes by accident.

### 6.6 What a kind may not do

Write anything, call the network, read other people's data into someone else's `summary`, or depend on the viewer. These keep results cacheable and the engine safe in a job.

### 6.7 Attestation

`checklist_attestations` (`person_id`, `key`, `statement`, `attested_at`, `attested_by_id`): "Physical on file", "Handbook read". The `attested` kind reads them. Who may attest is the item's setting: the person, a guardian for a ward (`Person#guardians`, the same people forms let sign), or a manager. Audited; never by or for oneself when the setting is "manager". It replaces a badge used as a manual flag. It is not how profile details are confirmed; that is a form (§13).

## 7. Excuses and adjustments

Two tools, one screen (an "Adjust" menu on an item row), kept distinct on purpose:

| | Excuse | Adjustment |
|---|---|---|
| What it does | Takes the item off this person: status `exempt`, label "Excused" | Adds or removes credit on a count item, with a reason; counts as confirmed |
| Works on | Any item; for attendance, one meeting | Count items only |
| Pooling | Excuses the person alone | Credits the whole group (credit pools) |
| Who | Managers of the checklist's team and above, and admins. Not organizers, not grant holders. | The item's organizers (as today) |
| Self-approval | Nobody excuses themselves or a relative | Nobody adjusts for themselves, a relative, or anyone in a group with either (`commitment.rb:154-165`) |

Why not one: an excuse answers "does this apply to them" and an adjustment answers "how much have they done"; making an adjustment large enough to finish a count is a quiet way to excuse, and the pooled and group-wide rules differ. Both are audited (`has_paper_trail`), listed on the checklist page. An excused item's result carries **who excused it and when** for anyone who sees the item at full level ("Excused by <name>, <date>"); the **reason** shows only to managers and admins (and, for adjustments, organizers). Others see "Excused" or the adjusted total, and both show the underlying number to those who may see it ("Excused; 22% of 14 h"). Excuse fields: `item_id`, `person_id`, `event_id` (optional), `reason`, `expires_on` (optional), `created_by`. The self/relative helper is copied into the checklists branch, not shared, so branches stay independent; for count items the group-wide `Commitment#self_or_relative_in_group?` is used.

For comparison, BL-003's "override badge the job respects" becomes the excuse table, with a reason and an audit trail.

## 8. Computed versus stored

### 8.1 Stored, with a computed fallback

Results are stored in `checklist_results` and read from there (150 people × 10 items = 1,500 rows). Reasons: predicates need an answer for many people as SQL (`Person.where(id: ChecklistResult.where(checklist: c, item_id: nil, status: :met).select(:person_id))`); a dashboard card per user can't run attendance for the roster; hooks need "what it was before".

Stored results are a **cache**: any row can be deleted and recomputed; nothing in them isn't derivable from data, excuses, attestations, adjustments and configuration. The one exception, "Record this list", is its own table (§9.4). A count item's `Progress` is still computed, never stored on the commitment; the result row is a copy for reading.

### 8.2 Keeping them right

1. **By change.** Each kind lists `invalidations`: `[Model, ->(record) { person ids or :all }]`. Core installs one `after_commit` concern on those models from a `to_prepare` initializer (as `Checkin.include(Signups::CheckinFulfilment)` does). A `Checkin`, `BadgeAssignment`, `Membership`, `TimeClockPunch`, `FormResponse`, `PersonFieldValue` change marks that person's rows; an `Event`, `TimeClockPeriod`, `Relationship` of a pooling type, a `CommitmentAdjustment` or a configuration change marks the whole checklist. Count items use their sources' `watches` (check-ins; `signup_changed.gatherpack`). `form_complete` also listens to `form_responses - incomplete` and the other form status events. Marking writes a unique row in `checklist_refreshes` and enqueues one job per checklist 30 seconds out, so a burst of punches is one recomputation. No work inside the user's save.
2. **By the clock.** Some answers change with no data change: a meeting ends, an event starts (planned becomes confirmed), a window, cutoff or relative edge passes, a form expires. Kinds return `next_change_at`; the checklist stores the earliest as `next_refresh_at`. A recurring job in `config/recurring.yml` refreshes checklists whose time has come. Absences are covered: a person who skipped writes no punch, but the meeting's end refreshes the whole checklist.
3. **Nightly full recomputation** per active checklist, which repairs anything missed.

**Reads.** `Checklist#status_for(person)` and the SQL scope read stored rows. If a person's rows are missing or older than `checklists_max_age_hours` (default 24), the read computes that one person, stores it, and returns it.

### 8.3 Hooks and events

Change detection happens in the refresh job, comparing old and new status; the job rescues and logs hook errors, so a bad hook can't affect anyone's save (`Hook#run` doesn't rescue).

- Hook event via `GatherPack::HookCatalog.register_events`: `checklist_results - status changed` (model is the result row; it carries `previous_status`; the overall is the row with `item_id` null). Targets registered for the new tables.
- `ActiveSupport::Notifications` `checklist_status_changed.gatherpack` (payload: result, previous status), following `person_field_changed.gatherpack`.
- First computation is silent, so building a checklist doesn't fire a hundred hooks. A "Backfill" reset also stays silent.

## 9. Time

### 9.1 Dates, windows, as-of, relative dates

Every evaluation takes a **window** and an **as-of moment**. The window is the item's dates or the checklist's. The as-of moment is now, or the cutoff when set and passed. Kinds are pure functions of (data up to as-of, config, window): re-running changes nothing, which makes refreshing safe and a late-corrected punch correct.

**Relative dates.** Every date field on an item, and the checklist's window, is a two-choice radio with the field inline: **on or after** [date], or **within the last** [N] [days | months]. A relative choice resolves against the as-of moment, so a standing checklist ("the last 12 months") needs no yearly edits. The clock refresh handles the moving edge. A range (attendance rule dates, the window) offers the same radio for its start; its end is "until <date>" or "now".

The report's period buttons become an **"as of" date picker** for organizers: it computes live and shows without storing (one full evaluation each, so organizers only).

### 9.2 Cutoff, so eligibility doesn't swing

`cutoff_on`: results are computed on data up to the end of that day (count items stop counting at the cutoff by shortening their period). Before the date, results are live and the report shows "Counting up to <date>" with today's numbers. After it, results stay as of the cutoff; a correction to older data still changes them. For a trip decided on a date, copy the checklist (§9.3), keep shared items through nesting, set a cutoff.

### 9.3 Copy to next year

"Copy checklist" duplicates population, items (count items get new commitment rows with the same settings and sources), grants and organizers, and clears excuses, adjustments, attestations, results and recorded lists. A second step shows **proposed changes for a person to confirm**, never applied silently:

- **Dates.** The window, every item's dates and every attendance rule's dates shift by an amount the organizer picks (default one year), shown old → new and editable. Relative dates stay as they are.
- **Replacements.** Any badge, team, form, event type, sheet or field whose name contains a year or date (`2027 FIRST Registered`, `Class of 2030`) is matched to a name with the shifted year, as a table "Old → New" with a pick for each unmatched one, which can be left as is.

The copy starts as `draft` and shows the preview (§9.6) before it's opened.

### 9.4 Changes while running, and record

Editing an active checklist is allowed. Each save is audited, shows a banner "Changed <date> by <role>: <what>", and shows an **impact preview before saving**: "3 people would go from Done to Not yet, 1 from Almost to Done" with names. Rules take effect for the whole window; no per-date versioning, because attendance rules already differ by date inside the kind and a policy that changes mid-way is a conversation, not a data model.

**Record this list** (first release) snapshots names, statuses and the configuration into `checklist_lists`, read-only, for a decision such as a trip roster. Results keep changing; the list doesn't.

### 9.5 Early denominators

After two meetings one absence is 50%. Each attendance rule has a **"judge after N meetings"** setting (default 0, so parity is exact; a team that wants a buffer sets 3 or 4). Below it the result is `pending` with "Counted after 4 meetings; 2 held". A weekly rule applies only to a week with held meetings.

### 9.6 Live preview

While editing an item or the population, a side panel "Who this passes" evaluates the **draft** (unsaved config in memory, nothing stored) for the population: counts by status with the first ten names each, a one-line sentence of the check in words, debounced via Turbo with a spinner for slow ones. Organizer-only. For a count item the draft needs no commitment row: `Progress` is built from an unsaved commitment with the draft settings.

### 9.7 Date housekeeping

Two optional settings, both dates:

- **Archive checklists ended before** a date (or N days after the end): the nightly job moves active ones to `archived` (read-only, off menus and dashboards, still openable). One another checklist requires is skipped and flagged.
- **Prune results** of archived checklists older than a date, keeping recorded lists and audit rows. Results are a cache, so pruning loses nothing recomputable.

"Archive forms older than X" is the same idea and belongs to forms, with the same date field.

## 10. Visibility, surfaces, tools

### 10.1 One visibility model

Results are computed for everyone and **shown by viewer**. For a viewer and a person, the viewer sees:

- Everything, as an admin, a manager of the checklist's team or above, or an organizer of the checklist.
- Everything the item allows (below) about themselves, and the overall.
- What a **grant** gives (§10.2).
- Nothing else: the checklist isn't in their list and the row isn't in the table. Omission is server-side, in the query that builds the rows.

Each item has **who sees it** (`read_level`): an `AudienceLevels` level, or `group`. Defaults:

| Item | Default who sees it |
|---|---|
| Condition item | The checklist's `read_level` (default `family`: the person, guardians, leaders) |
| Count item with pooling | `group`: the person, people related to a member of their pooled group through the pooling relationship type (a parent), and leaders |
| Count item without pooling | `self_and_leaders`: the person and their leaders. **Guardians don't see it** unless the item is set to `family` |
| Overall | The checklist's `read_level` |

This is the settled Commitments rule (`PersonCommitmentsPolicy`) written in the one model: a parent sees a pooled family count because the parent is grouped by the relationship; a student-only count stays hidden from parents unless someone sets it to `family`. The My GatherPack setting `commitments_guardians_see_progress` is the same choice made once for everything; here it is made per item, so that setting is superseded. `Commitment#group_relative_of?` (`commitment.rb:241`) implements `group`; the person's own pooled group names show only at `group` level and above, others get the status.

Two levels per item: **status** (badge and label) and **full** (summary, detail, measures, fix link). A measure marked `owner_only` (attendance "extra") shows only to the person, guardians and leaders. Order and filters use only what the viewer can see.

Guardian parts show only to a viewer who is a guardian (a ward's block, "Fix it for <name>" buttons).

### 10.2 Grants

`checklist_grants`: `checklist_id`, `badge_id` or `team_id`, `item_ids` (empty = overall only), `access` (`status`, `full`). Holders of the badge, or members of the team (and below), see the overall plus the listed items for everyone the checklist covers. Only admin-assigned badges can grant (`form_badge_grant.rb:15`, `:33`), so nobody grants themselves access. Managers of a granted team can widen it, the trust the Page extends today. This is the whole of the three viewer tiers in §14.5.

### 10.3 Using a checklist as a test in other features

```
Checklists.meets?(checklist, person, accept: :met)   # or accept: [:met, :pending]
Checklists.people_meeting(checklist, accept:)        # a Person relation
Checklists.people_covered_by(checklist)              # everyone it covers
```

Strict by default (`met` or `exempt`); a caller may accept `pending` where signing up is the way to finish. Callers:

- **Sign-up position rule** `checklist` (a fourth kind: "is done", or "is done or almost"). Needs an enum value and a column in `signup_position_rules`, in a connector branch editing the signups feature.
  - What a rule shows follows §10.1 per viewer: the person, and anyone who may see their result, get the real answer. Organizers and people signing someone up who can't see the result get no per-person badge and, on a refusal, a fixed reason naming only the checklist. A refused sign-up still tells them the person doesn't meet it; that is accepted, since the gate can't work without refusing.
- **Form audience rule** target `checklist`: asked of people who finish it, don't, or everyone it covers (how applicants, on no team yet, get the joining forms; intake §10.6). Connector in `feature_forms`.
- **Checklists page, profile tab, dashboard card** (§10.4).

**Reading results.** Two calls, both from stored results with no per-person queries:

```
Checklists.checklist_for(person)                   # every checklist covering this person, as the viewer may see it
Checklists.status_for(checklist, people, viewer:)  # { person_id => Status }; Status has overall and ordered
                                                   #   items: label, status, summary, detail (if allowed), fix,
                                                   #   acts_for (the person or their guardian), excuse {by, at, reason?}
```

One checklist for one person and their wards is `status_for(checklist, [person, *person.wards], viewer: person)`. A team's applicants (about 200 rows for the approval page) is `status_for(checklist, applicants, viewer:)`: two queries (the overall rows and the item rows) plus the visibility lookups, whatever the size; a test asserts the query count. Visibility (§10.1) is applied inside the call, so a caller can't over-show.

### 10.4 Surfaces (one set)

- **Report page** `/checklists/:id`: one row per visible person; columns overall plus each visible item; click-to-sort headers; per-column tick filters ("Showing people with any of the ticked values"; columns combine); min/max filters on measures; name filter; the **overall column filter includes "isn't Done"** (Almost, Not yet and Not counted together), which is "who hasn't come back"; shared print styles; a "Your family" section above "Everyone" when the viewer sees more for their own and their wards' rows. Same behavior as the Page, no ERB. A count item shows `confirmed of owed`; its drill-down is the old commitment page (sources, breakdown, how to earn).
- **Edit page** `/checklists/:id/edit` holds all setup, in order: basics (own Save), Items, Who it covers (with the "Who this passes" preview), Who else can see everyone's results, Organizers, then Delete (only for those allowed). Adding a checklist, and every setup add/remove/cancel, returns to the matching Edit section; a single item's rules return to that item's edit page. The report page holds no setup: results, then "Recorded lists" (organizers, once one exists), with Edit, Record, Recompute and Copy as buttons.
- **Profile tab** "Checklists": the person's checklists as plain lists with fix links; hidden when none cover or are visible to the viewer. Replaces the Commitments tab.
- **Dashboard card** "My sign-ups and checklists" (the current card, relabelled): upcoming sign-ups and each checklist with unfinished items the viewer can fix, as a progress line.
- **My GatherPack** to-do and its progress section read the same API.
- **Sign-up hint** (§6.2) and the sign-up sheet panel "What this counts toward".
- **Explain** (§10.5).
- **MCP** (§12.4).

### 10.5 Explaining a person's status

> **Not eligible.** Attendance: 22% of Build hours so far; needs 40% each week (week of Jan 12: 1 h of 3 h). Consent form: not signed. [Sign it]
> **Pending.** Outreach: 1 event signed up, 0 done. [See events]
> **Done.** Login, FIRST registered, Academic eligibility, Concessions (family: 3 of 3 shifts).

Unmet items first, then almost, then done. A fix link is the kind's best next action: a form to fill or sign again (the guardian's link if the viewer is the guardian), a sign-up sheet or event list for a count item, an "I confirm" button (attestation), or "Ask a mentor" for something only a manager can do.

## 11. Moving Commitments in

Commitments is live in production. The change keeps its tables, code and every caller working, and shows users only checklists.

### 11.1 Existing commitments appear as checklists

A data migration (`Checklists::WrapCommitments`, idempotent, reversible: `down` removes wrapper checklists and their items, never commitment rows) creates, for each commitment without an item:

- a **checklist** with the commitment's title, team, window `starts_on..ends_on`, status `active`, `read_level` `family`;
- population rules generated from `owing_team`, `owing_badge` and `exempt_badge` (so the population is identical);
- the commitment's organizers copied to the checklist's;
- one **count item** (`commitment_id` set) with the commitment's unit, amounts, `counts_when` and pooling, and `read_level` unset (so the default in §10.1 applies: the same visibility as today).

A test asserts, for every commitment, that `owing_people`, `progress(people)` and visibility are identical before and after. Wrappers are ordinary checklists: an organizer can add items to one, rename it, or later **move** its count item into another checklist (the item's population then becomes that checklist's, shown in the §9.4 preview before it applies).

**Titles stay.** The commitment's `title` is set once when the item is created and not renamed when the item's label changes, because the Eligibility Report Page finds commitments by title. Remove this rule when the Page retires.

### 11.2 New count items make their commitment row

Creating a count item creates its `Commitment` row (team = the checklist's team, owing team = the same, dates and amounts from the item) and the item edits it. The commitment's own population and organizer questions are answered by the item, through a module prepended in `feature/checklists-count`'s initializer (no edit to `commitment.rb`):

- `owing_people` returns the checklist population narrowed by the item's rules, when the commitment has an item; its own columns otherwise (a commitment never wrapped still works);
- `organizer?` returns the checklist's organizer check when it has an item;
- `period_times` reads the item's resolved dates.

`Commitment#progress`, `progress_for`, `group_for`, `covers?`, the sources and the adjustments are untouched, so the Page, the sign-up hint, MCP and `SignupsSummary` keep working.

### 11.3 Surfaces fold in

- **Sidebar:** one "Checklists" item. The Commitments item is hidden when checklists are on (see branch edits).
- **Pages:** `/commitments` index, show and `/people/:id/commitments` redirect to the checklist (or the profile tab) for the commitment's item. The nested source, adjustment and organizer routes stay, now reached from the item's screens; their views are reused inside the item form.
- **Profile tab, dashboard card, sign-up hint:** read checklist items (§10.4).
- **Switch:** `feature_checklists` is the one visible switch. With it on, Commitments is treated as on (count items need it); `feature_commitments` stays as the dependency and is no longer offered separately.
- **Organizers setting:** `checklists_organizers` has the same grammar as `commitments_organizers`; while it is blank, `commitments_organizers` is read, so no one is locked out on upgrade.
- **MCP:** the four commitment tools keep working with their current inputs and results (commitment ids, same permissions) and are described as superseded by the checklist tools; remove them when no client calls them (owner's call). The checklist tools cover them (§12.4). Parity: the aliases and the new tools call the same code, so they cannot disagree.
- **Code names:** `Commitment`, `CommitmentSource`, `CommitmentAdjustment`, `CommitmentOrganizer`, the `Commitments` module and tables stay. Renaming a live table buys nothing a user can see and risks the audit trail and neat ids. New code is `Checklist*`.

### 11.4 Branches that change

| Branch | Change |
|---|---|
| `feature/commitments` | `features.rb` entry (line ~195): hides its sidebar item and follows `feature_checklists` when that is on. The redirect for `CommitmentsController`/`PersonCommitmentsController` is added from `-count`, not here. `commitments_organizers` text notes the new setting. |
| `feature/signup-credit` | `Commitments::SignupHint` text and the sheet panel read items: "left on <item> (<checklist>)", visibility per §10.1. `commitments_crediting` joins to items. |
| `feature/signups-widget` | `SignupsSummary` reads checklist items for the "commitments" half; card relabelled "My sign-ups and checklists". |
| `feature/commitments-profile-tab` | Tab hidden when checklists are on; replaced by the Checklists tab. |
| `feature/mcp-commitments` | Tools marked superseded in their descriptions; behavior unchanged. |
| `feature/checklists`, `-count`, `-attendance`, `-person-fields`, `-forms`, `-signups`, `feature/mcp-checklists`, `feature/my-gatherpack-checklists` | New (§12.1). |
| My GatherPack spec | References to `PersonCommitmentsPolicy`, "commitments" sections and `commitments_guardians_see_progress` follow the renames in §10.1 and §10.4; `feature/commitments-guardian-view` is replaced by the per-item "who sees it". The lead edits that spec. |

`signups-spec.md` §4 is left alone.

## 12. Build

### 12.1 Branches and flags

| Branch | Based on | Contents |
|---|---|---|
| `feature/checklists` | `upstream/main` + `feature/person-fields` + `feature/extension-registries` | Flag, tables, registry, base kind, evaluator, refresh, results, excuses, grants, attestations, population rules, report, profile tab, settings, hooks, copy, record, housekeeping; kinds `badge`, `team_member`, `has_login`, `age`, `attested`, `checklist`, `any_of`. Written to be an upstream PR unchanged. Depends on person-fields (audience levels, guardianship) and extension-registries (settings and hook seams). |
| `feature/checklists-attendance` | `feature/checklists` | `attendance`, excused meetings. Needs only upstream time clock and events. |
| `feature/checklists-count` | `feature/checklists` + `feature/commitments` | `count` kind, the wrap migration, delegation module, redirects, item form (sources, adjustments, how to earn) |
| `feature/checklists-person-fields` | `feature/checklists` + `feature/person-fields` | `person_field` |
| `feature/checklists-forms` | `feature/checklists` + `feature/forms` | `form_complete`, form audience target |
| `feature/checklists-signups` | `feature/checklists` + `feature/signups` | Position rule kind `checklist`; sheet panel |
| `feature/mcp-checklists` | `feature/mcp` + `feature/checklists` | Tools (§12.4) |
| `feature/my-gatherpack-checklists` | `feature/my-gatherpack` + `feature/checklists` | To-do section, family page |

A `+` is a declared dependency. Connectors register from their own initializer, guarded by `Checklists.respond_to?(:register_item_kind)` and the feature being present, like `mcp_commitments.rb`. A kind whose feature is off shows as unavailable and counts as `not_met` with a problem notice, never a silent pass.

Flag: `feature_checklists`, default off (rule 10). With it off nothing changes: Commitments works as today, no menu item, no callbacks (the invalidation concern returns at once).

### 12.2 Settings and registrations

- `Settings.register(:checklists_organizers, :text, "Checklist Organizers", "", "Checklists", ...)`: `Badge name > Highest team name` per line, same grammar and rule as `commitments_organizers`; admin-assigned badges only.
- `Settings.register(:checklists_max_age_hours, :integer, ..., "24", "Checklists", ...)`; optional housekeeping dates (§9.7).
- Hook catalog: targets for the new tables and the one event (§8.3).
- Sidebar: People section via the `Features` registry. Profile tab: registry. No view edits.

### 12.3 Data

New tables (neat prefixes `chkl_`, `chli_`, …):

| Table | Columns |
|---|---|
| `checklists` | `team_id`, `title`, `description`, `starts_on`, `starts_within` (N, unit; null = fixed), `ends_on`, `cutoff_on`, `status`, `read_level`, `met_word`, `pending_word`, `not_met_word`, `next_refresh_at`, `computed_at`, `created_by_id` |
| `checklist_organizers` | `checklist_id`, `person_id` |
| `checklist_items` | `checklist_id`, `kind`, `config` jsonb, `commitment_id` (count items; unique), `label`, `position`, `counts`, `starts_on`, `ends_on`, relative equivalents, `due_on`, `read_level`, `exempt_label`, `parent_id` |
| `checklist_rules` | `checklist_id`, `item_id` (null = checklist), `effect`, `target_type` (team, badge, person, applicants), `team_id`, `badge_id`, `person_id`, `include_managers` |
| `checklist_grants` | `checklist_id`, `badge_id`, `team_id`, `item_ids` (uuid array), `access` |
| `checklist_results` | as §5.4; unique `(checklist_id, item_id, person_id)`; index `(checklist_id, item_id, status)` |
| `checklist_excuses` | `item_id`, `person_id`, `event_id`, `reason`, `expires_on`, `created_by_id` |
| `checklist_attestations` | `person_id`, `key`, `statement`, `attested_at`, `attested_by_id` |
| `checklist_lists` | `checklist_id`, `recorded_at`, `recorded_by_id`, `note`, `rows` jsonb, `configuration` jsonb |
| `checklist_refreshes` | `checklist_id`, `person_id` (null = all), `created_at`; unique |

All migrations are new and reversible; none touches an upstream or existing fork migration (rule 9). The wrap migration only inserts. References from a checklist or item to a badge, team, field, form or commitment are protected on delete with a readable error (`dependent: :restrict_with_error`, as `commitments.rb` does), and shown as a **problem** on the checklist page if it happens anyway.

Upstream files touched (to go in `FORK.md`): `config/routes.rb`, `config/recurring.yml` (two jobs), `db/schema.rb` (regenerated). Connectors also touch `signup_position_rule.rb` and `form_audience_rule.rb` (enum values and a nullable `checklist_id`), both fork features. Everything else is a new file, a registry entry, a prepended module or a `to_prepare` include on `Checkin`, `BadgeAssignment`, `Membership`, `TimeClockPunch`, `Event`, `FormResponse`, `PersonFieldValue`, `CommitmentAdjustment`.

### 12.4 MCP

`feature/mcp-checklists`, tools allow exactly what the app allows; nothing wider than the page:

- `list_checklists`; `checklist_status` (a person's results as the caller may see them); `checklist_results` (a checklist's rows as the report would show the caller; includes count items' numbers).
- `add_credit_adjustment` and `remove_credit_adjustment` for count items (organizers, group-wide self rule, reason kept out of the log).
- `excuse_item` and `remove_excuse` (managers and admins only; self and relatives refused with the app's message).
- `attest_item` where the app lets the caller.
- Old `list_commitments`, `commitment_progress`, `add_commitment_adjustment`, `remove_commitment_adjustment` stay (§11.3). No tool edits a checklist's configuration: the edit screens hold the preview, impact check and audit.

### 12.5 Sample data

`fork/sample_data/features/checklists.rb`, plus one file per connector branch (`checklists-attendance.rb`, `-count.rb`, `-person-fields.rb`, `-forms.rb`). A Northwind checklist "Trip Eligibility" with one person in each situation: done on everything, almost (signed up, not done), not yet (below the share), exempt (excluded team), excused (with a reason), no birthday, blank field, a pooled family with a count item, a ward and guardian, an applicant-only person; a leader with a team grant. Existing `commitments.rb` sample data gets wrapped by the migration, as a test of §11.1. Names are roles or neutral placeholders.

### 12.6 Tests

- Each kind: batch equals one-person evaluation; missing data; deleted reference; timing (`travel_to`).
- Count items: results equal `Commitment#progress` for pooled, ungrouped, capped, planned/confirmed, deduped and adjusted cases; narrowed population; relatives' credit; cutoff shortens the period; relative dates resolve into the commitment period.
- **Wrap migration:** for every fixture commitment, `owing_people`, `progress`, organizer and visibility are unchanged; reversible; idempotent.
- Attendance parity with the Page on a fixed dataset (overlap, early leave, late stay, pools, weekly failing one week, extra hours, leeway, period-boundary events per BL-002, excused meeting, no meetings yet, judge-after-N).
- Forms: older, expired (`Expired <date>`, `Good until <date>`), open newer draft, relative window; cache refresh on `form_responses - incomplete`.
- Overall rule, `any_of` in `any_of` (with a count item inside), deep nesting, cycle rejection, applicability and exemptions.
- Refresh: change marks only the right people; clock refresh at a meeting's end and at an expiry; nightly repairs a missed row; hooks fire once on a change and never on first computation; a failing hook doesn't stop the job.
- Visibility: every tier in §14.5 as a controller test; the three default rows of §10.1 (pooled count seen by a parent, ungrouped count hidden from a parent until set to `family`); sort/filter can't reveal a hidden value; grant by a non-admin badge rejected; guardian sees a ward.
- Excuses vs adjustments: self and relative refused in both; managers-only excuses; group-wide adjustment rule; audit rows.
- Redirects from `/commitments` and `/people/:id/commitments`; old MCP tools unchanged.
- Copy: date shift, replacement table, count items get new commitment rows, nothing else copied. Housekeeping by date. Predicates: `people_meeting` is a relation, strict by default.
- Performance: a 200-person, 10-item checklist (two count items) evaluates in a bounded number of queries.
- Flag off: no routes, tab, callbacks or job work; Commitments untouched.
- MCP: parity with controller tests for the same viewer.

## 13. What intake needs from this

The intake spec has no seasons, season enrollments or form renewal switches: membership is the record, and a returning member sees items older than an item's date as needing redoing. Its joining checklist is a checklist. What it gets:

| Intake need | Provided by | Notes |
|---|---|---|
| People not yet on a team (applicants) | Population rule target `applicants` (§5.1): pending `MembershipApplication`s to a team | Intake creates the `MembershipApplication` when a self-service entry is verified, or at once at the kiosk, so every applicant has a population entry. |
| Redo what's older than a date | `form_complete`, signed in the item's date window and not expired (§6.4) | Reads the response status and `activated_at`. Intake owns the form's expiry column and `FormResponse#expires_at`; this spec only reads them. The form must be open to be signed again. |
| A login | `has_login` | |
| Guardian acting on a ward's checklist | Results are per person; a guardian's `family` level reaches their ward (`audience_access.rb:31`); each result's `fix` is a link or an attest action the guardian may take | Uses `Person#guardians`/`wards` (`person.rb:116-121`). Guardian text appears only when the viewer is a guardian. |
| Kiosk "my checklist" | `Checklists.checklist_for(person)`: ordered items `{label, status, summary, fix: {label, path | attest_key}}` from stored results | A kiosk shows only items with a fix it can do |
| Completion → become a member | Notification `checklist_status_changed.gatherpack` and hook `checklist_results - status changed` on the overall row | Intake owns the reaction. The checklist only reports. |
| One checklist for a person and their wards; a team's applicants (about 200 rows) | `Checklists.status_for(checklist, people, viewer:)` (§10.3), stored results, constant queries | Items carry `acts_for`, `fix` and `excuse {by, at, reason?}` |
| Guardian-signed form with no guardian linked | `form_complete` says "Needs a guardian linked" with a fix to add one; "Waiting for <guardian>'s signature" is Almost (§6.4) | Not yet, not Almost, when none is linked |
| Applicants asked the joining forms | Form audience target `checklist` (§10.3); a person outside a form's audience is Not yet and a problem is listed, never exempt | |
| "Who hasn't come back" | The report's overall filter "isn't Done" (§10.4) | |
| Next year's checklist | Copy checklist (§9.3) | |

Not provided: payments as an item, and any step that writes data. There is no season in the engine or its tables.

## 14. HBR setup appendix: today's report as one checklist

All data in the screens, no code.

### 14.1 The checklist

**2026-27 Eligibility.** Team "Team 1747" (top), window 2026-05-01 to 2027-04-30; no cutoff. Words: Eligible / Pending / Not eligible. `read_level`: family. **Population:** include team "Team 1747 - Students" with and below, **members only**.

### 14.2 Items (one per report column)

| # | Column | Kind | Settings | Applies to / exempt | Counts |
|---|---|---|---|---|---|
| 1 | 1747 Status | `has_login` | | | yes |
| 2 | FIRST Status (roster) | `badge` | `2027 FIRST Registered` | | no |
| 3 | FIRST Status (consent) | `badge` | `2027 FIRST Consent Signed` | | yes |
| 4 | Concessions | `count` | Unit "shifts"; amount 2, plus 1 per additional student in a family; pooled by Parent/Guardian; sources: check-ins at "Concessions" (a "Shifts" answer is the quantity), check-ins at "Concessions Stocking" at 3 count as 1; counts when confirmed; dates 2026-05-01 to 2027-01-09 | | yes, `due_on` 2027-01-09 (shows "Missed") |
| 5 | Outreach | `count` | Unit "events"; amount 1; source check-ins at "Outreach"; no pooling; **who sees it: family** (so parents see it as the Page does today) | exclude team "Team 1747 - Class of 2030" and badge "Rookie 2026-27", exempt label "Rookie" | yes |
| 6 | Attendance | `attendance` | dates default to the window; extra hours off; judge after 0 meetings; leeway 1 min; rules below | | yes |
| 7 | Academic Eligibility | `person_field` | `academically_eligible`, "is any of" Yes, blank counts as Yes | | yes |

Attendance rules: **Off-Season Summer** 2026-05-01 to 2026-08-31, 10%, counted together with **Off-Season Fall** 2026-09-01 to 2026-12-31, 20%; **Build/Competition** 2027-01-01 to 2027-04-30, 40%, weekly, judged on its own. These are the Page's three rows. The Page looks at one period at a time; the checklist looks at the dates, so results can differ (listed in §14.6).

Overall: any `not_met` → Not eligible; any `pending` (signed up, not done) → Pending; else Eligible. Item 2 and "No meetings yet" don't count against anyone.

### 14.3 Column-by-column check

| Report | Checklist |
|---|---|
| Eligibility (overall, sort order) | Overall; sort by overall, then number unmet, then percent (same order as `sorts["eligibility"]`) |
| 1747 Status | #1 detail "Has a GatherPack login" / "No GatherPack login with an email yet" |
| FIRST: Consent signed / Needs consent / Not registered, with sync date | #2 + #3. Needs consent = #2 done, #3 not yet; the sync date is the badge description's line, shown in detail |
| Concessions: Met / Signed up / Not yet / Missed, "Family (names): n of m shifts" | #4 done / almost / not yet; "Missed" from `due_on`; pooled text from `Progress`, names shown at `group` level |
| Outreach: Met / Signed up / Rookie / Not yet | #5 (exempt label "Rookie") |
| Attendance badge and lines "✓ Off-Season: n% of h (needs 10%)" | #6 detail lines, one per group; "Below minimum" label; "No meetings yet" |
| Meetings, Hours at meetings, Attendance %, Extra hours; number filters | #6 measures (`extra` owner-only) |
| Academic Eligibility Yes/No | #7 |
| Tick filters, number min/max, name filter, counts | Report page (§10.4) |
| Print layout, "Printed" line | Report page prints with the shared report print styles |
| Period buttons | "As of" picker (§9.1); the rules' dates |
| Admin alert box for missing teams, badges, field, relationship type | "Setup problems" from each kind's `problems` |

### 14.4 Other pages

| Page | Becomes |
|---|---|
| `safety-training-report.html.erb` (missing a badge, with guardian contacts) | A checklist "Safety training" with one `badge` item, "Not yet" as the saved default filter, and an optional **Guardians' contacts** column that appears only when the viewer can already see those guardians. The class sort stays a report option |
| `outreach-report.html.erb` | The Outreach column, plus the item's own page; retire once checked |
| `academic-eligibility.html.erb` | Stays a Page (a bulk field editor); the item reads the field |
| `clocked-in-report.html.erb` | Stays a Page: a live safety view, not a status |
| `attendance-report.html.erb` | The attendance item's per-person drill-down; stays until parity |

### 14.5 Viewer tiers

| Tier | Today | Configuration |
|---|---|---|
| Admins and managers of the top team | See all | Admin; manager of the checklist's team |
| Student Leadership team | Whole roster: name, overall, attendance; details only for themselves and wards | Grant: team "Team 1747 - Student Leadership", item Attendance, `full`, minus owner-only extra hours. Their own and wards' details come from `family` |
| "Eligibility Report Viewer" badge | Same | Grant: that badge, same item and access (admin-assigned badge) |
| Everyone else | Themselves and wards | `read_level` family; nothing in the query for anyone else |

Leaders see two sections as today ("Details for you and your wards", then "Team"); their sort and filters are limited to the columns they see.

### 14.6 Parity

The Page's cells carry `data-filter` and `data-value` (`badge_cell`, Page line 393). A script run in an admin session on staging fetches the Page and the checklist and compares per person and column: overall, each item's status, the numbers. Each difference is a bug or a recorded intentional change (leeway, "blank" handling, "Pending" semantics, dates versus one period). It passes when repeated runs over real data agree for every person. The Page stays reachable and unlinked until then.

## 15. Decisions

1. **One feature: Checklists.** Requirements and Commitments become one. A commitment is a count item; condition items are the other family. One answer per person.
2. **Typed item kinds with small fixed forms; presets by copy.** No expression language, no generic builder.
3. **Count items run on the existing Commitments engine.** Tables, `Progress`, sources, dedupe, pooling and adjustments are unchanged; only the form around them is new.
4. **`any_of` and `checklist` nest freely;** the only structural limit is no cycles. No NOT, no expressions.
5. **Results are stored, as a rebuildable cache,** refreshed by change, by clock and nightly, with a computed fallback. Predicates use the stored rows.
6. **Evaluation is a pure function of data up to an as-of moment.** Cutoffs fall out of that. Hooks never run inside user saves.
7. **No separate check-in condition kind.** Counting activity is a count item.
8. **Excuses** are reasoned, audited, no self- or relative approval, by managers and admins only. **Adjustments** stay distinct (count only, group-wide, organizers) (§7).
9. **One visibility model:** per item "who sees it", defaults in §10.1 reproduce the settled Commitments rule; omission is server-side; two levels; `owner_only` measures; grants only by admin-assigned badge or team. `commitments_guardians_see_progress` is superseded by the per-item choice.
10. **Missing data is "not yet" by default,** with the reason shown; "blank counts as" only where blank is a value. "Nothing to judge yet" is `exempt` with a label, or `pending` under a minimum.
11. **No season, year or period concept.** A checklist's dates are its window; an item's default to it. Copying shifts dates and proposes replacements for a person to confirm.
12. **Every date is configuration,** as "on or after <date>" or "within the last N days/months".
13. **Carry-over is part of building an attendance rule:** judged on its own or counted together with named others; no engine default.
14. **Attestation** is a generic manual check (replacing badges as flags); confirming profile details is a form.
15. **`form_complete` reads the response status** (`complete?`, `needs_reconfirmation`, `expires_at`) and applies the item's date window on top.
16. **Predicates are strict by default;** a caller may accept `pending`.
17. **Edits while running are allowed** with a preview and an audit, not versioned per date.
18. **"Record this list" ships in the first release.**
19. **Existing commitments are wrapped as one-item checklists on their existing tables;** code and table names stay, users see "checklist". Commitment titles are frozen while the Page needs them.
20. **Date housekeeping is configuration:** archive checklists ended before a date, prune old results.
21. **Flag off by default; connectors per feature;** upstream files touched are routes, recurring jobs, schema, and two rule enums in connector branches.
22. **Generalist code.** Overall words, labels and exempt labels are data; no "student", "travel" or "concession" in code or kind names; no month assumed.
23. **No timing in this spec.** Order is by dependency (§17).
24. **The word "commitment" is dropped from everything users see;** a count item is "Count". Code and table names stay (§11.3).
25. **No automatic email on Done → Not yet.** The hook and the notification (§8.3) exist for anyone who wants one.
26. **"Judge after N meetings" is a per-rule setting,** default 0.
27. **A form item for someone outside the form's audience is Not yet, with a problem listed,** never exempt. The fix is the form audience target `checklist`.
28. **A guardian-signed form says "Needs a guardian linked" when the person has none,** separate from "waiting for the guardian's signature". No extra kind.
29. **Closed or draft forms, and forms closing inside the window, are problems** shown to organizers.
30. **Results are read through `status_for` (batch, viewer-filtered) and `checklist_for`;** excuses expose who and when, reasons to managers and admins.
31. **The report's overall filter includes "isn't Done".**

## 16. Open questions

None.

## 17. Build order

By dependency only:

1. `feature/checklists` core, with `badge`, `has_login`, `team_member`, `age`, `attested`, `checklist`, `any_of`; report, profile tab, excuses, grants, preview, copy, record, housekeeping.
2. `feature/checklists-attendance`.
3. `feature/checklists-count` (needs `feature/commitments`): count kind, wrap migration, delegation, redirects. Then the edits to `feature/signup-credit`, `feature/signups-widget`, `feature/commitments-profile-tab` and `feature/mcp-commitments` (§11.4).
4. `feature/checklists-person-fields` and `feature/checklists-forms`.
5. Parity against the Page (§14.6) over real data.
6. `feature/mcp-checklists` and `feature/my-gatherpack-checklists`.
7. Predicates (`feature/checklists-signups`, form audience target), then `ledger_balance`, `hours`.

Backlog: BL-003 is superseded; BL-002 stays on its own branch (an upstream bug independent of this).
