# Spec: Requirements

Status: rev. 2, 2026-11-06. Not built. Code facts checked against integration `49609326`. Decisions are in §14; open questions are in §15. Companion: `membership-intake-spec.md` (what it needs from this is §12).

Rev. 2: dates, not seasons. There is no season, year or period concept; every check that looks at time takes a date or a date range (§5.2, §6.1), and `form_complete` also honours a form's own expiry. Combining has no depth limits (§5.3). Copy to next year shifts dates (§9.3). Date housekeeping is §9.7.

Supersedes [BL-003](../backlog/BL-003-attendance-eligibility-badge.md) (a badge kept in step with attendance). Does not depend on [BL-002](../backlog/BL-002-period-hours-date-bounds.md); the attendance check reads meetings itself (§6.2).

## 1. Goal

Organizers say what a person must have, do or be, and GatherPack answers for every person, in words: **met**, **pending**, **not met**, or **not counted**, with why and how to fix it. The answer is available as a report, on the profile, on a person's own to-do page, in hooks, and as a test other features can use ("only people who meet this").

The test is whether an organizer can rebuild today's Eligibility Report (about 700 lines of admin-written ERB with settings at the top) with screens only, and whether next year's copy takes minutes, not an evening. §13 does this on paper.

### 1.1 Non-goals

- A programming or formula language for organizers (§3).
- Replacing Commitments. Commitments count "earn N of something" and stay the place for quotas, pooling and credit sources. Requirements read them (§6.1).
- Per-person scoring, ranking or points.
- Writing anything back as a badge. A badge as a status flag goes stale (BL-003); the stored result here is the alternative (§8).
- Names for HBR's policies in code. "Students", "travel", "concessions" appear only in §13, as configuration.

### 1.2 Use cases

| Use case | Verdict | How |
|---|---|---|
| Eligibility over a span of dates: attendance share by month, registration, a roster badge, a signed form, a person field, a quota | Fits | One set, one requirement each (§13) |
| Pooled-by-family quota counts toward an individual's status | Fits | `commitment_met` reads Commitments' own grouping |
| Pre-trip decision on a date, so it doesn't swing | Fits | Cutoff date on the set (§9.2) |
| A manager excuses a missed meeting, or waives a requirement for one person (rare; kept so there is a way) | Fits | Excuses, managers and admins only, no self-approval (§7) |
| Joining checklist for a new member (confirm profile, sign forms, get a login) and applicants not yet on a team | Fits | Applicant population, dated `form_complete`, `has_login` (§12) |
| "Missing safety training, with guardian contacts" list | Fits | Filter "Not met", optional contacts column (§13.4) |
| Position or form open only to people who meet a set | Additive | Predicate (§10.3); needs a small change in each of those branches |
| Dues or ledger balance not negative | Additive, later | `ledger_balance` kind |
| Hours worked in a window (build hours) | Additive, later | `hours` kind |
| "Has a guardian on file with an email" | Additive, later | `has_guardian` kind |
| Recently active (check-in or punch in the last N days) | Additive, later | `recent_activity` kind |
| "Can still reach the minimum" projection for the rest of the window | Additive, later | Option on `attendance` |
| Record the list as decided for a trip | Fits | "Record this list" (§9.4) |
| Any-of rules across different data ("badge OR form") | Fits | `any_of` group (§5.3) |
| Arbitrary formulas over several attributes | Non-goal | Add a kind instead (§3) |
| Live "who is clocked in" page | Non-goal | Stays a Page; it isn't a status |
| Bulk editing a person field (Academic Eligibility page) | Non-goal | Stays a Page; the engine only reads the field |

## 2. How it works today

- **The report is a Page.** `pages/eligibility-report.html.erb` computes everything inside one ERB: attendance rules by month with pools and weekly checks (lines 146–200), concessions with its own family pooling (217–260), outreach and rookies (261–277), FIRST badges (304–318), an academic person field (319–322), the overall rule (324–345), badge labels and filters (356–420), viewer tiers (`manager_view`, `leader_view`, `full_view`, lines 100–112). Pages run with `ERB.new(...).result(binding)` and only admins can author them (`pages_helper#format_page_content`, gp-map "Executable content").
- **It already prefers Commitments.** When `concessions_commitment` and `outreach_commitment` titles exist, the report reads `commitment.progress(people)` and drops its own tally. The commitment kind in §6.1 is that code, made a feature.
- **Visibility is done by hand.** Each tier is built by choosing which model scope to read (`pundit_policy_scope` for managers, `.all` for leaders) and then omitting columns server-side. Every new report repeats this.
- **Computed every render.** Nothing is stored. A page load recomputes attendance for the whole roster. Nothing else can use the result: a sign-up position or form audience can't ask "is this person eligible", which is why the answer was copied into badges (BL-003).
- **No season, and none needed.** GatherPack has no season or year model (checked: no `Season` class, no `season` column in `db/schema.rb`). Everything that needs time already takes dates: Commitments use `starts_on`/`ends_on` (`app/models/commitment.rb:51-52`); time clock periods have `start_time`/`end_time` date columns (`db/schema.rb:1116`) and events link to a period (`events.time_clock_period_id`, `schema.rb:275`).
- **Commitments** (the pattern to follow): credit source kinds in a registry (`Commitments.register_source`, `app/models/commitments.rb:38`; interface `Commitments::SourceKind`, `commitments/source_kind.rb`), with `records(person_ids)` batch reads; population = owing team + owing badge − exempt badge (`commitment.rb:170-175`); `commitment.progress(people)` batch API (`commitment.rb:188`); organizers by badge grant setting (`commitment.rb:76-116`, `config/initializers/commitments.rb`); no self- or relative-approval (`commitment.rb:144-165`); visibility by `PersonCommitmentsPolicy` (`app/policies/person_commitments_policy.rb`); profile tab via `GatherPack::Feature::ProfileTab` (`config/initializers/commitments_profile_tab.rb`); `SignupsSummary` for the dashboard card.
- **Audience levels** (`app/models/audience_levels.rb`) and `AudienceAccess` already answer "is this viewer the subject, a guardian, a leader or a teammate of that person", one object per (viewer, subject) pair. Form badge grants (`form_badge_grant.rb`) let admin-assigned badges widen access.
- **Hooks fire inside the save** (`CanBeHooked` after_create/after_update) and `Hook#run` does not rescue (`app/models/hook.rb:47`). Hooks for a derived status must therefore fire from a job, not a callback (§8.3).
- **Predicates are closed.** Sign-up position rules are an enum of three kinds (`signup_position_rule.rb:19`: badge, age, team); form audience rules are team, badge or person (`form_audience_rule.rb:16`). Neither has a registry.

## 3. Options for flexibility

The ask is flexibility without a configuration nightmare. Four ways to get it:

| Option | Looks like | Strength | Why it fails here |
|---|---|---|---|
| A. Expression language or Ruby | `attendance >= 0.4 and has_badge("X") or ...` | Anything is expressible | Only admins could write it. No live "who passes" until it runs. Can't be explained to a parent in words. Typos break a whole set. The app already has `eval` in Pages, hooks and reports, and the security audit (80 findings) is a reason to add no more. |
| B. Generic attribute / operator / value builder | Pick "Attendance share", "is at least", "40" | Familiar from filter UIs | The attributes aren't columns. Attendance share needs meeting overlap, month rules and weekly checks; a family's shifts need pooling; "signed up but not yet done" needs a third state. A generic builder either can't say these or hands people primitives to assemble them, which is the nightmare. |
| C. Typed check kinds, each with a small fixed form | "Attendance" with its rules table; "Has badge"; "Person field is…" | Each kind knows its data, its missing-data case, its explanation and its fix link. The form is only the questions that kind needs. Previewable and explainable. | A new need means a new kind (a small additive change, and the registry makes it a connector branch). |
| D. Presets / templates | "Start from 2026-27 Eligibility" | Fast, fewer decisions | Not an engine; a way to use one. |

**Recommendation: C as the engine, D on top.** Kinds are the vocabulary; a set is a list of them; **copy to next year** (§9.3) and sample sets are the presets. B survives only inside kinds, where the operators are fixed by the data type (a person field of type choice offers "is any of"; a date field offers "on or after"). That is the "native over config" rule: the screens say what the data is, not how to query it.

How the three hard parts stay small:

- **Combination.** A set is "all of" its requirements. `any_of` groups requirements when one of several is enough, groups can hold groups, and a set can require another set (§5.3). Only cycles are refused. No NOT, no precedence rules to learn.
- **Parameters.** A kind's form has at most a handful of fields. Dates default to the set's window and can be overridden on the requirement (§5.2).
- **Exceptions.** Not "and not rookie" logic: a requirement can say who it doesn't apply to (§5.2), and a person can be excused (§7).

## 4. Concepts

| Concept | Meaning |
|---|---|
| Requirement set | A named list of requirements for a population over a window of dates ("2026-27 Eligibility"). Belongs to a team. Has organizers. |
| Population | Who the set covers: rules to include or exclude a team, badge, person, or applicants to a team (§5.1). |
| Requirement | One check inside a set: a check kind and its settings, a label, whether it counts toward the overall answer, optional window, who it doesn't apply to, who may see it. |
| Check kind | A registered type of check (`attendance`, `badge`, …). Provides settings, a batch evaluation, a plain-words explanation and a fix link. |
| Result | The stored answer for one person and one requirement: status, summary, detail, numbers, when computed. One more row per person for the set's overall. |
| Status | `met`, `pending`, `not_met`, `exempt` (label: "Not counted", "Rookie", "No meetings yet", "Excused", set by the kind or the exemption). |
| Overall | Any required requirement `not_met` → not met; else any `pending` → pending; else met. `exempt` is ignored. |
| Excuse | A manager's or admin's reasoned exception for one person, on a requirement or on one meeting (§7). |
| Grant | Lets holders of a badge, or members of a team, see a set's overall and chosen requirements for everyone it covers (§10.2). |
| Attestation | A recorded "this is right / this is done" by the person, a guardian, or an organizer (§6.5). |
| Window | The set's `starts_on`..`ends_on`. A requirement's dates default to it and can be overridden. |

## 5. Model

### 5.1 Set and population

A set has: `team` (the reach, and who may run it), `title`, `description`, `starts_on`, `ends_on`, optional `cutoff_on` (§9.2), `status` (`draft`, `active`, `archived`, same meanings as forms), three overall words (default "Met", "Pending", "Not met"; HBR sets "Eligible", "Pending", "Not eligible"), `read_level` (an `AudienceLevels` level, default `family`: the person, their guardians and their leaders), `created_by`.

**Population rules** reuse the shape of `FormAudienceRule`: include or exclude a team (with or without managers), a badge's holders, or one person. One new target type, **applicants**: people with a pending `MembershipApplication` (`schema.rb:595`) to a team (the intake spec's pre-members). Rules are computed whenever needed; people who join later are covered automatically. Same rule as Commitments: the set's population must be within the set's team and below, except applicants, who are within the team they applied to.

Rules live in `requirement_rules` (set-level when `requirement_id` is null).

### 5.2 Requirement

Fields: `kind`, `config` (jsonb, validated by the kind), `label`, `position`, `counts` (true: affects overall; false: shown only, such as "FIRST registered"), optional `starts_on`/`ends_on` overriding the set's window (**every kind that looks at time reads these**; §6.1), optional `due_on` (when not met after this date, the label reads "Missed"), `read_level` (default the set's), `exempt_label`.

**Applies to.** The same rule table, with `requirement_id` set: rules narrow who the requirement covers (include) or exclude people (exempt). Someone outside it gets status `exempt` with `exempt_label` ("Rookie"). This replaces the hard-coded rookie list: a class team is an exclusion rule; hand-listed exceptions are a badge.

### 5.3 Combining

- A set's requirements are "all of": every counting requirement must be met.
- **`any_of`** is a kind that holds child requirements. Met when any child is met; else pending when any child is pending; else not met; the result line says which one passed. A child can be an `any_of` or any other kind, to any depth (`requirements.parent_id`). The editor draws each group as a box headed "Any one of these is enough"; nested boxes indent.
- **`requirement_set`** is a kind pointing at another set: met when the person meets it (or isn't covered by it, `exempt`). "Trip eligibility" = "Eligibility" + attendance on top. No depth limit.
- UI rule from the product: several picks on one screen mean "any of", and the screen says so: "Any of: [badge] [badge]". A kind whose picks are "all of" says "All of" (`form_complete` with several forms).

**Limit kept, and why.** One: **no cycles** (a set that requires itself, directly or through others, never settles). Checked on save by walking the references. There is no depth or size cap: a nested set is read from its own stored results (§8), so cost does not grow with depth, and the editor draws nesting recursively. If a huge tree ever slows the editor, a cap goes on the editor, not the model. Deliberately absent: NOT and expressions (a "not" is an exclusion rule on the requirement, §5.2).

### 5.4 Result and status

`requirement_results`: `requirement_id` (null = overall), `requirement_set_id`, `person_id`, `status`, `summary` (short, one line: "2 of 3 shifts"), `detail` (text, the full explanation), `measures` (jsonb: named numbers such as `meetings`, `hours`, `percent`, for columns and filters), `fix` (jsonb: `{label, path, action}`), `previous_status`, `changed_at`, `computed_at`, `stale`.

Missing data never silently passes. Each kind says what missing means in its settings (default **not met**, with the reason in the detail: "No birthday on file"). Where the data is legitimately optional, the kind offers "Blank counts as…" (the person field kind, so a blank Academically Eligible counts as Yes). A kind with nothing to judge yet returns `exempt` with a label ("No meetings yet"), or `pending` when the organizer sets a minimum (§9.5).

## 6. Check kinds

A kind is a class registered with `Requirements.register_kind(:badge, Requirements::Kinds::Badge)`, the same shape as `Commitments.register_source`. Interface (a base `Requirements::CheckKind`):

```
self.label / self.settings          # fields for the editor (typed: badges, teams, field, form,
                                    #   number, percent, date, choice, rules table)
self.problems(config)               # deleted badge, missing field... shown to organizers
evaluate(people, context)           # BATCH: { person_id => Result }; context carries window,
                                    #   as_of, cutoff, and the set. Never one query per person.
explain(result)                     # the plain-words sentence (stored as detail)
self.invalidations                  # which records, when changed, make which people stale (§8.2)
self.next_change_at(config, ctx)    # next moment the answer can change with no data change (§8.2)
self.measures                       # named numbers, each: label, type, owner_only?
```

Evaluation reads data directly, without the viewer's permissions (a leader reading attendance, a parent reading a ward's family tally); **visibility is enforced when results are shown (§10)**, never inside a kind. A kind never puts more in `summary` than the lowest viewer of that requirement may see.

### 6.1 Core and connector kinds

| Kind | Branch | Settings | Met / pending / not met | Missing data |
|---|---|---|---|---|
| `commitment_met` | `-commitments` | A commitment | Met: `progress.met?`. Pending: confirmed + planned reaches owed (signed up, not yet done). Not met: otherwise. Exempt: the commitment doesn't cover them ("Doesn't owe"). | Not covered → exempt |
| `attendance` | `-attendance` | Period (current or a chosen one), rules table, extra hours count, minimum meetings (§6.2) | Per-rule groups all pass → met | No meetings yet → exempt "No meetings yet" |
| `badge` | core | Badges, any of; optional "assigned on or after" | Holds any (assigned in the dates, if asked) | Deleted badge → problem shown, not met |
| `team_member` | core | Teams, any of (with those below); optional "joined on or after" | In any | — |
| `has_login` | core | — | A `User` with an email | No user → not met, fix: "ask a leader to invite you" if the viewer can't |
| `age` | core | Min and/or max; on a chosen date (default the window's end) | In range | No birthday → not met "No birthday on file"; the result shows pass/fail, never the date |
| `person_field` | `-person-fields` | A field; operator by its type (is any of, is not, on or after, at least, is filled in); "blank counts as"; optional "last changed on or after" | Per operator | Blank → by "blank counts as" (default not met) |
| `form_complete` | `-forms` | Forms (all of); **signed** on or after a date or within the last N days/months (default the window's start), or "ever" | Reads the response's status, not `activated_at` alone. Met: `complete?` and the active submission's `activated_at` is in the date window. Pending: a newer draft or pending submission is open, or a signer is awaited. Not met: no response, `needs_reconfirmation` (including the expired reason), or signed before the window. Detail: "Good until <date>" when `FormResponse#expires_at` is set; "Expired <date>" when expiry is why it's not met (fix: sign again). | Not in the form's audience → exempt |
| `attested` | core | A statement, who attests (the person, a guardian or the person, a manager); optional "on or after" | Met: attested on or after the date (default the window's start) | — (§6.5) |
| `requirement_set` | core | Another set | Its overall | Not covered → exempt |
| `any_of` | core | Child requirements | See §5.3 | — |

**Dates on every kind that looks at time.** Each such kind has a date or range field, defaulting to the set's window and overridable per requirement. `commitment_met` is the exception: a commitment has its own period, which the requirement reads. Because the date is on the requirement, one badge or form can serve several sets with different windows, and a copy only changes dates.

**Signed on or after, with no change to forms.** `FormSubmission` records `activated_at` (`schema.rb:384`). A returning member whose active submission is older is "not met" and the existing flow lets them sign again: `FormResponsesController#update` calls `start_submission!` (`form_responses_controller.rb:28`), which starts a new draft from the active answers and gets a new `activated_at` on submit. The fix link is that form. Coordination with intake: a form can be answered only while open (`form_access.rb:72`), so a form being re-signed must be open; and if the form page doesn't offer a new version on an already complete response, that is the one forms change, made in `feature/forms`.

**Form expiry vs the requirement's date.** The form may carry its own expiry ("responses expire on <date>" or "good for N months"; its design is the intake spec's). `form_complete` reads the response's status (`complete?`, `needs_reconfirmation`); intake §7.5 puts expiry there as an `:expired` reconfirmation reason with `FormResponse#expires_at`, so the engine never recomputes expiry. The requirement's date window applies on top, using `activated_at`. Use the **form's expiry** when the rule belongs to the form everywhere ("the media release is good for a year", wherever it's asked); use the **requirement's date** when it's one checklist's rule ("signed since Sept 1 for this trip").

Later (§1.2): `ledger_balance`, `hours`, `has_guardian`, `recent_activity`. Check-ins at an event type are deliberately **not** a kind: a commitment of 1 does it (Decision 6), so there is one way to count activity.

### 6.2 Attendance in detail

Takes the report's logic unchanged, made batch and testable:

- **Meetings** are events linked to the chosen time clock period that have ended (`end_time < now`, or `<= cutoff` when one applies). The kind queries events itself with day bounds in `Time.zone`, so BL-002's date bug doesn't touch it (the report does the same by not calling `available_hours`).
- **Credit** is only punched time that overlaps a meeting (merged intervals); leaving early costs, staying late adds nothing. `extra_hours_count` lets extra time make up missed time within the same group, never above 100%.
- **Rules** are rows the organizer builds: name, dates (a date range; the screen offers "every May–Aug" shortcuts that fill in the dates), share of meeting hours, `weekly` (every week must pass separately), and how the rule relates to the others. Each rule either stands alone (its meetings are judged by themselves, so a weak summer doesn't count against fall) or joins a named `pool` (rules in a pool are summed and checked together). Nothing about periods, seasons or carry-over is built into the kind: whether earlier meetings count toward a later rule is the organizer's choice on the rule, and the screen says which it is ("Judged on its own" / "Counted together with: Summer"). HBR's Page learned this the hard way: summer meetings counted into fall until the rules were split.
- **Measures** (columns and filters): `meetings` attended of held, `credited` hours, `percent`, `extra` (owner-only).
- **Tolerance.** The report passes a group at `got + 1 >= needed` (one second). The kind settings call it "Leeway" in minutes, default 1, so parity is exact and the owner can change it.
- **Meetings to look at.** Events linked to a time clock period (that link is how GatherPack knows a meeting is one) that start within the rule's dates. By default every period overlapping the requirement's dates is used; a requirement may name periods to narrow it. Nothing is tied to "the current period"; a past view uses the as-of picker (§9.1).
- **Excused meetings.** A manager or admin can excuse a person from one meeting (§7); that meeting leaves that person's required hours and credited hours.

### 6.3 Why a kind, not a Page, for FIRST

The FIRST roster sync already writes two badges per year (`2027 FIRST Registered`, `2027 FIRST Consent Signed`). A requirement reads them with the `badge` kind. The sync keeps owning the data; the report never needs to know it exists.

### 6.4 What a kind may not do

Write anything, call the network, read other people's data into someone else's `summary`, or depend on the viewer. These keep results cacheable and the engine safe to run in a job.

### 6.5 Attestation

`requirement_attestations` (`person_id`, `key`, `statement`, `attested_at`, `attested_by_id`): "I confirm this is right", "Handbook read", "Physical on file". The `attested` kind reads them. Who may attest is the requirement's setting: the person (the person's own to-do button), a guardian for a ward (only `Person#guardians` of the person, the same people forms let sign), or a manager (a mentor ticking a box). Attesting is audited and never done by or for oneself when the setting is "manager" (same rule as excuses). This is the engine's answer to "badge as status flag" for manual checks, for things like "Physical on file". It is not how profile details are confirmed; that is a form (§12).

## 7. Excuses (overrides)

A manager or admin excuses a person from a requirement (whole), or from one meeting for the attendance kind. This isn't a common need (HBR doesn't do it today); it exists so there is a recorded way when it's needed, instead of editing punches. Fields: `requirement_id`, `person_id`, `event_id` (optional), `reason` (required), `expires_on` (optional), `created_by`. The result becomes `exempt`, label "Excused", detail "Excused: <reason>" for viewers allowed to read reasons (managers and admins); others see "Excused".

- **No self-approval.** Nobody can excuse themselves or anyone related to them by any relationship type; the button is missing with the reason on the page. Same code shape as `Commitment#self_or_relative?` (`commitment.rb:144`); copied, not shared, so each branch stays independent.
- **Who may excuse:** admins and managers of the set's team and above. The set's organizer list and grant holders can't.
- **Audit:** `has_paper_trail` on excuses, like every organizer change. The set page lists current excuses.
- **Not a way to hide a failure.** The overall is computed with the excuse; the underlying number stays visible to organizers ("Excused; 22% of 14 h").

For comparison, BL-003's "override badge the job respects" becomes this table, with a reason and an audit trail.

## 8. Computed versus stored

### 8.1 Stored, with a computed fallback

Results are **stored** in `requirement_results` and read from there. A set with 150 people and 10 requirements is 1,500 rows. Reasons:

- Predicates (a sign-up position, a form audience, a dashboard card) need an answer for many people at once, as SQL: `Person.where(id: RequirementResult.where(requirement_set: set, requirement_id: nil, status: :met).select(:person_id))`. A computed answer can't be a subquery.
- A dashboard card per signed-in user can't run attendance for the roster.
- Hooks need "what it was before" to detect a change.

Stored results are a **cache**: any row can be deleted and recomputed; there is no state in them that isn't derivable from data, excuses, attestations and the set's configuration. (The one exception, "Record this list", is its own table, §9.4.)

### 8.2 Keeping them right

Three refreshers; the third is the one the BL-003 hook idea lacked.

1. **By change.** (`form_complete` also listens to `form_responses - incomplete` and the other form status events, so an expired item never stays Met. Its `next_change_at` is the earliest upcoming `expires_at`, so the clock refresh (2.) covers expiry even if no status event has fired yet.) Each kind lists `invalidations`: `[Model, ->(record) { person ids or :all }]`. Core installs one `after_commit` concern on those models from a `to_prepare` initializer (as `Checkin.include(Signups::CheckinFulfilment)` does). A `Checkin`, `BadgeAssignment`, `Membership`, `TimeClockPunch`, `FormResponse`, `PersonFieldValue` or credit-source change marks that person's rows for the sets that use the kind; an `Event`, `TimeClockPeriod`, `Commitment` or set-configuration change marks the whole set. Marking writes a row in `requirement_refreshes` (set, person or null, unique) and enqueues one job per set 30 seconds out, so a burst of punches is one recomputation. No hook, no work inside the user's save.
2. **By the clock.** Some answers change with no data change: a meeting ends, an event starts (planned becomes confirmed), a window or cutoff passes. Kinds return `next_change_at(config, context)`; the set stores the earliest as `next_refresh_at`. A recurring job every 10 minutes (`config/recurring.yml`, next to `form_schedule_job`) refreshes sets whose time has come. Absences are covered by this: a student who skipped writes no punch, but the meeting's end refreshes the whole set.
3. **Nightly full recomputation.** One run per active set, which also repairs anything missed.

**Reads.** `RequirementSet#status_for(person)` and the SQL scope read stored rows. If a person's rows are missing or older than `requirements_max_age_hours` (setting, default 24), the read computes that one person's results, stores them, and returns them. A set never shows "nothing" because a job is behind.

### 8.3 Hooks and events

Change detection happens in the refresh job, comparing old and new status; the job rescues and logs hook errors, so a bad hook can't affect anyone's save (contrast `Hook#run`, which doesn't rescue, `hook.rb:47`).

- Hook events via `GatherPack::HookCatalog.register_events`: `requirement_results - status changed` (model is the result row; it carries `previous_status`). The overall answer is the same event on the row whose `requirement_id` is null. Targets registered for the new tables: `requirement_sets`, `requirements`, `requirement_excuses`, `requirement_attestations`.
- `ActiveSupport::Notifications` `requirement_status_changed.gatherpack` (payload: result, previous status) for other features (My GatherPack, intake), following `person_field_changed.gatherpack`.
- First computation is silent (no `previous_status`), so building a set doesn't fire a hundred hooks. A "Backfill" reset also stays silent.

## 9. Time

### 9.1 Dates, windows, as-of

Every evaluation takes a **window** and an **as-of moment**. The window is the requirement's own dates or the set's. The as-of moment is now, or the cutoff when one is set and passed. Kinds are pure functions of (data up to as-of, config, window): re-running changes nothing, which is what makes refreshing safe and a late-corrected punch correct.

The report's period buttons become an **"as of" date picker** for organizers: it computes live and shows without storing, and is limited to organizers (it does the work of one full evaluation). This is how a past period is looked at.

**Relative dates.** Every date field on a check, and the set's window, is a two-choice radio with the field inline: **on or after** [date], or **within the last** [N] [days | months]. The relative choice is resolved against the as-of moment, so a standing set ("good for the last 12 months") needs no yearly edits. Results refresh by the clock when a relative edge moves (`next_change_at`, §8.2), and copy to next year (§9.3) leaves relative fields as they are. A date range (attendance rule dates, the set's window) offers the same radio for its start; its end stays "until <date>" or "now".

### 9.2 Cutoff, so eligibility doesn't swing

`cutoff_on` on a set: results are computed on the data up to the end of that day. Before the date, results are live and the report shows a banner "Counting up to <date>" with today's numbers ("if the date were today"). After it, results stay as of the cutoff. A correction to older data (a punch fixed, a meeting added) still changes them, because it is data before the cutoff. For a trip decided on a date, copy the set (§9.3), keep the shared requirements through `requirement_set` nesting, and set a cutoff.

### 9.3 Copy to next year

"Copy set" duplicates population, requirements, grants and organizers, and clears excuses, attestations, results and recorded lists. A second step shows **proposed changes for a person to confirm**, never applied silently:

- **Dates.** The set's window, every requirement's dates and every attendance rule's dates shift by an amount the organizer picks (default one year), shown old → new and editable.
- **Replacements.** Any badge, team, form, commitment or person field whose name contains a year or date (`2027 FIRST Registered`, `Class of 2030`) is matched to a name with the shifted year, as a table "Old → New" with a pick for each unmatched one, which can be left as is.

The copy starts as `draft` and shows the §9.6 preview before it's opened. Nothing season-like is created or looked up.

### 9.4 Changes while running, and record

Editing an active set is allowed. Each save is audited (PaperTrail), shows a banner "Changed <date> by <role>: <what>", and shows an **impact preview before saving**: "3 people would go from Met to Not met, 1 from Pending to Met" with the names (organizers already see them). Rules take effect for the whole window; there is no per-date rule versioning, because attendance rules already differ by month inside the kind (the HBR case) and a policy that changes mid-way is a conversation, not a data model.

"Record this list" (first release, phase 3) snapshots names, statuses and the configuration into `requirement_lists`, read-only, for the decision on a trip. Results keep changing; the list doesn't.

### 9.5 Early denominators

After two meetings one absence is 50%. The attendance kind has **minimum meetings held** (default 0 so parity with today is exact; the owner picks, §15). Below it the result is `pending` with the detail "Counted after 4 meetings; 2 held". A weekly rule never has this problem: it applies only to a week with held meetings. The "can still reach the minimum" projection is later (§1.2).

### 9.6 Live preview

While editing a requirement or population, a side panel "Who this passes" evaluates the **draft** (unsaved config, in memory, nothing stored) for the set's population:

- Counts by status with the first ten names each; click through to the full list.
- A one-line sentence of the check in words ("Anyone in Students except the Class of 2030, who has at least 40% of Build meeting hours, every week").
- Runs as a Turbo request, debounced; a slow one shows a spinner and the counts arrive when ready. Organizer-only (the people it lists are people the organizer can already see).

### 9.7 Date housekeeping

Two optional settings, both dates:

- **Archive sets ended before** a date (or N days after `ends_on`): the nightly job moves matching active sets to `archived` (read-only, off menus and dashboards, still openable). A set another set requires is skipped and flagged.
- **Prune results** of archived sets older than a date, keeping recorded lists (§9.4) and audit rows. Results are a cache (§8.1), so pruning loses nothing that can't be recomputed.

"Archive forms older than X" is the same idea and belongs to forms, with the same date field.

## 10. Visibility

### 10.1 Rules

Results are computed for everyone and **shown by viewer**. For a viewer and a person, the viewer sees:

- Everything, as an admin, a manager of the set's team (or above), or an organizer of the set.
- Everything about themselves and the people they are guardian of, because the set's `read_level` (default `family`) reaches the person, their guardians and leaders. Per requirement, `read_level` can be narrower (`leaders`).
- What a **grant** gives (§10.2).
- Nothing else: the set isn't in their list, the row isn't in the table. Omission is server-side, in the query that builds the report rows, never a hidden column.

Two levels per requirement: **status** (the badge and label) and **full** (summary, detail, measures, fix link). A measure marked `owner_only` by its kind (attendance "extra hours") shows only to the person, guardians and leaders.

Order and filters use only what the viewer can see; a viewer with status-only access can sort by overall and name, not by a number they don't see.

`commitment_met` results are further limited by the commitment's own rule: viewers who `PersonCommitmentsPolicy` wouldn't show that commitment get the status only, and the detail with names of a family group goes only to the person, organizers and group relatives. Already-settled: visibility follows grouping.

Guardian parts show only to a viewer who is a guardian (a ward's block, the "Fix it for <name>" buttons).

### 10.2 Grants

`requirement_grants`: `requirement_set_id`, `badge_id` or `team_id` (exactly one), `requirement_ids` (empty = overall only), `access` (`status`, `full`). Holders of the badge, or members of the team (and below), see the **overall** plus the listed requirements for everyone the set covers, at that level. Only badges admins assign can grant (the `FormBadgeGrant` rule, `form_badge_grant.rb:43`), so nobody can assign themselves access. A team grant is honored for members of that team and below; managers of that team can therefore widen it, the same trust the report extends today.

This is the whole of the three viewer tiers in §13.5.

### 10.3 Using a set as a test in other features

Other features ask "does this person meet it" through one API:

```
Requirements.meets?(set, person, accept: :met)   # or accept: [:met, :pending]
Requirements.people_meeting(set, accept:)        # a Person relation, for audience rules
```

Both read stored results (§8.2 fallback). Default is **strict** (`met` only; `exempt` counts as met). A predicate may accept `pending` where signing up is the way to finish (a position). Callers:

- **Sign-up position rule** `requirement_set`: a fourth rule kind with "is met" or "is met or pending". Needs the enum extension and a column in `signup_position_rules`, so it lives in a connector branch that edits the signups feature (listed in §11).
- **Form audience rule** target `requirement_set`: forms asked only of people who meet a set (or who don't: the exclude effect), or of everyone the set covers ("People this list covers", via `Requirements.people_covered_by(set)`). The covered choice is how applicants, who are on no team yet, get the joining forms (intake §13.6). Same connector approach, `feature_forms`.
- **Checklists** (§12) and the **profile tab / dashboard** (§10.4).

### 10.4 Surfaces

- **Report page** `/requirement_sets/:id`: one row per visible person; columns overall plus each visible requirement; click-to-sort headers; per-column tick filters ("Showing people with any of the ticked values"; columns combine); min/max filters on measures; name filter; shared print styles (landscape, "Printed <date>" line); set-level "Your family" section above "Everyone" when the viewer sees more for their own and their wards' rows than for others. Same behavior as the Page today, no ERB.
- **Profile tab** "Requirements": the person's sets, each a plain checklist with fix links. Visible by the same rule (§10.1) and hidden when none cover the person.
- **My GatherPack** to-do: sets with any `not_met` or `pending` item the viewer can fix, as a card per person (the viewer and their wards). A section in `feature/my-gatherpack-requirements`.
- **Dashboard card** like `SignupsSummary` for people with unfinished items.
- **Explain** (§10.5).
- **MCP** (§11.4).

### 10.5 Explaining a person's status

The profile checklist and a row's "Why?" show plain words, built from each result's `detail` and `fix`:

> **Not eligible.** Attendance: 22% of Build hours so far; needs 40% each week (week of Jan 12: 1 h of 3 h). Signed Consent form: not signed. [Sign it]
> **Pending.** Outreach: 1 event signed up, 0 done. [See events]
> **Met.** 1747 login, FIRST registered, Academic eligibility.

The overall sentence lists unmet items first, then pending, then met. A fix link is the kind's best next action: a form to fill or sign again (the guardian's link if the viewer is the guardian), a sign-up sheet, an "I confirm" button (attestation), or an instruction for something only an organizer can do ("Ask a mentor").

## 11. Build

### 11.1 Branches and flags

| Branch | Based on | Contents |
|---|---|---|
| `feature/requirements` | `upstream/main` | Flag, tables, registry, base kind, evaluator, refresh, results, excuses, grants, attestations, population rules, report, profile tab, settings, hooks; kinds `badge`, `team_member`, `has_login`, `age`, `attested`, `requirement_set`, `any_of`. Written to be an upstream PR unchanged. Depends on nothing. |
| `feature/requirements-attendance` | `feature/requirements` | `attendance` kind and excused meetings. Needs only upstream time clock and events. |
| `feature/requirements-commitments` | `feature/requirements` + `feature/commitments` | `commitment_met` |
| `feature/requirements-person-fields` | `feature/requirements` + `feature/person-fields` | `person_field` |
| `feature/requirements-forms` | `feature/requirements` + `feature/forms` | `form_complete`, form audience rule target |
| `feature/requirements-signups` | `feature/requirements` + `feature/signups` | Position rule kind `requirement_set` |
| `feature/mcp-requirements` | `feature/mcp` + `feature/requirements` | Tools (§11.4) |
| `feature/my-gatherpack-requirements` | `feature/my-gatherpack` + `feature/requirements` | To-do section, family page checklist |

A `+` is a declared dependency, as in `my-gatherpack-spec.md`. Connectors register their kind from their own initializer, guarded by `Requirements.respond_to?(:register_kind)` and the feature being present, like `mcp_commitments.rb`. A kind whose feature is off is shown as unavailable and counts as `not_met` with a problem notice, not a silent pass.

Flag: `feature_requirements`, default off (rule 10). Every connector rides on it. With it off nothing changes: no menu item, no tab, no job work, no callbacks (the invalidation concern returns at once).

### 11.2 Settings and registrations

- `Settings.register(:requirements_organizers, :text, "Requirement Organizers", "", "Requirements", ...)`: who may run sets without managing a team, one per line `Badge name > Highest team name`, the same grammar and rule as `commitments_organizers` (`commitment.rb:76`). Admin-assigned badges only.
- `Settings.register(:requirements_max_age_hours, :integer, "Requirement Results Max Age", "24", "Requirements", ...)`.
- Hook catalog: targets and the one event (§8.3).
- Sidebar: People section, "Requirements" via the `Features` registry. Profile tab: registry. No edit to either view.

### 11.3 Data

New tables (neat id prefixes `reqs_`, `req_`, `reqr_`, … following `has_neat_id`):

| Table | Columns |
|---|---|
| `requirement_sets` | `team_id`, `title`, `description`, `starts_on`, `ends_on`, `cutoff_on`, `status`, `read_level`, `met_word`, `pending_word`, `not_met_word`, `next_refresh_at`, `computed_at`, `created_by_id` |
| `requirement_set_organizers` | `requirement_set_id`, `person_id` |
| `requirements` | `requirement_set_id`, `kind`, `config` jsonb, `label`, `position`, `counts`, `starts_on`, `ends_on`, `due_on`, `read_level`, `exempt_label`, `parent_id` (an `any_of` child) |
| `requirement_rules` | `requirement_set_id`, `requirement_id` (null = set), `effect`, `target_type` (team, badge, person, applicants), `team_id`, `badge_id`, `person_id`, `include_managers` |
| `requirement_grants` | `requirement_set_id`, `badge_id`, `team_id`, `requirement_ids` (uuid array), `access` |
| `requirement_results` | as §5.4 plus unique index `(requirement_set_id, requirement_id, person_id)` and an index on `(requirement_set_id, requirement_id, status)` |
| `requirement_excuses` | `requirement_id`, `person_id`, `event_id`, `reason`, `expires_on`, `created_by_id` |
| `requirement_attestations` | `person_id`, `key`, `statement`, `attested_at`, `attested_by_id` |
| `requirement_refreshes` | `requirement_set_id`, `person_id` (null = all), `created_at`; unique |

All migrations are new and reversible; none touches an upstream migration (rule 9). References from a set or requirement to a badge, team, field, form or commitment are protected on delete with a readable error (`dependent: :restrict_with_error` from the initializer, as `commitments.rb` does), and also as a **problem** on the set page if it somehow happens.

Upstream files touched (estimate, to go in `FORK.md`): `config/routes.rb`, `config/recurring.yml` (two jobs), `db/schema.rb` (regenerated). Connectors also touch `signup_position_rule.rb` and `form_audience_rule.rb` (enum values and a nullable `requirement_set_id`), both fork features. Everything else is a new file, a registry entry or a `to_prepare` include on `Checkin`, `BadgeAssignment`, `Membership`, `TimeClockPunch`, `Event`, `FormResponse`, `PersonFieldValue`. No edit to a view.

### 11.4 MCP parity

`feature/mcp-requirements` (tools allow exactly what the app allows; no MCP-only limits, nothing wider than the page):

- `list_requirement_sets`: sets the caller can see.
- `requirement_status`: a person's results as the caller may see them (status-only or full per requirement).
- `requirement_results`: a set's rows as the report would show the caller.
- `excuse_requirement` and `remove_excuse`: managers and admins only, as in the app; refuse self and relatives with the app's message; the reason is kept out of the log (`filter_parameters`, as `mcp_commitments.rb:6-9`).
- `attest_requirement`: for the cases the app lets the caller attest.

No tool to edit a set's configuration: the edit screens are the control surface, and the preview, impact check and audit live there.

### 11.5 Sample data

`fork/sample_data/features/requirements.rb` (and one file per connector branch: `requirements-attendance.rb`, `-commitments.rb`, `-person-fields.rb`, `-forms.rb`), following the existing files. A Northwind set "Trip Eligibility" with one person in each situation: met on everything, pending (signed up, not done), not met (below the share), exempt (excluded class team), excused (with a reason), no birthday, blank field, a ward and guardian pair, an applicant-only person; a leader with a team grant; attendance data across two weeks with a weekly rule failing on one. Names are roles or neutral placeholders.

### 11.6 Tests

- Each kind: batch evaluation equals a one-person evaluation; missing data; deleted reference; timing (planned versus confirmed with `travel_to`).
- Attendance: parity with the Page's numbers on a fixed dataset (overlap, early leave, late stay, pooled rules, weekly rule failing in one week, `extra_hours_count`, leeway, period boundary events per BL-002, excused meeting, no meetings yet, minimum meetings).
- Overall rule, `any_of` in `any_of`, deep nesting, cycle rejection, dated `form_complete` (older, expired, open newer draft) and `badge`, applicability and exemptions.
- Refresh: change marks only the right people; clock refresh at a meeting's end; nightly repairs a missed row; a second run changes nothing; stale fallback computes one person; hooks fire once on a change and never on first computation; a failing hook doesn't stop the job.
- Visibility: every tier in §13.5 as a controller test (what appears in the HTML, not what is hidden); sort/filter can't reveal a hidden value; grant by non-admin badge rejected; guardian sees a ward; commitment detail withheld per commitment visibility.
- Excuses: self and relative refused; expiry; audit row.
- Copy: date shift, replacement table, no results copied. Housekeeping: archive and prune by date.
- Predicates: `people_meeting` is a relation and strict by default.
- Performance: a 200-person, 10-requirement set evaluates in a bounded number of queries (assert query count, no N+1).
- Flag off: no routes, tab, callbacks or job work.
- MCP: parity with controller tests for the same viewer.

## 12. What intake needs from this

The intake spec has no seasons, season enrollments or form renewal switches: membership is the record, and a returning member sees items older than a requirement's date as needing redoing. Its joining checklist is a requirement set. What it gets:

| Intake need | Provided by | Notes |
|---|---|---|
| People not yet on a team (applicants) | Population rule target `applicants` (§5.1): pending `MembershipApplication`s to a team | Intake creates the `MembershipApplication` when a self-service entry is verified, or at once at the kiosk, so every applicant has a population entry. |
| Redo what's older than a date | `form_complete`, **signed on or after** the requirement's date, and **not expired** (the response's status, §6.1) | Reads `activated_at`; an older or expired signature is not met, with the form as the fix. Intake owns the form's expiry column; this spec only reads it. Coordination: the form must be open to be signed again; if the form page doesn't offer a new version on a complete response, intake and this spec agree one small change in `feature/forms`. |
| A login | `has_login` | |
| Guardian acting on a ward's checklist | Results are per person; a guardian's `family` read level reaches their ward (`audience_access.rb:31`); each result's `fix` is a link or an attest action the guardian may take | Uses `Person#guardians`/`wards` (`person.rb:116-121`), like forms. Guardian text appears only when the viewer is a guardian. |
| Kiosk "my checklist" | `Requirements.checklist_for(person)`: ordered items `{label, status, summary, fix: {label, path | attest_key}}` from stored results | A kiosk shows only items with a fix it can do |
| Completion → become a member | Notification `requirement_status_changed.gatherpack` and the hook event (§8.3), overall row | Intake owns the reaction. The engine only reports. |
| Next year's checklist | Copy set (§9.3) with shifted dates | |

Not provided: payments as a requirement, and any step that writes data. There is no season in this engine or its tables.

## 13. HBR setup appendix: today's report as configuration

All of this is data in the screens, no code. It is the proof the engine covers the Eligibility Report.

### 13.1 The set

**2026-27 Eligibility.** Team "Team 1747" (top), window 2026-05-01 to 2027-04-30 ; no cutoff. Words: Eligible / Pending / Not eligible. `read_level`: family (the person, guardians, leaders).

**Population:** include team "Team 1747 - Students" with and below, **members only** (the report's `manager: false`).

### 13.2 Requirements (one per report column)

| # | Column | Kind | Settings | Applies to / exempt | Counts |
|---|---|---|---|---|---|
| 1 | 1747 Status | `has_login` | | | yes |
| 2 | FIRST Status (roster) | `badge` | `2027 FIRST Registered` | | no |
| 3 | FIRST Status (consent) | `badge` | `2027 FIRST Consent Signed` | | yes |
| 4 | Concessions | `commitment_met` | "Concessions 2026" | none (the commitment exempts those who don't owe) | yes, `due_on` 2027-01-09 (shows "Missed" after) |
| 5 | Outreach | `commitment_met` | "Outreach 2026–27" | exclude team "Team 1747 - Class of 2030" and badge "Rookie 2026-27", exempt label "Rookie" | yes |
| 6 | Attendance | `attendance` | dates default to the window; extra hours off; minimum meetings 0; leeway 1 min; rules below | | yes |
| 7 | Academic Eligibility | `person_field` | `academically_eligible`, "is any of" Yes, blank counts as Yes | | yes |

Attendance rules table: **Off-Season Summer** 2026-05-01 to 2026-08-31, 10%, pool "Off-Season"; **Off-Season Fall** 2026-09-01 to 2026-12-31, 20%, pool "Off-Season"; **Build/Competition** 2027-01-01 to 2027-04-30, 40%, weekly, judged on its own. These are the Page's three rows. The Page looks at one period at a time; the set looks at the dates, so results can differ (listed in §13.6).

The commitments keep what they have today: family grouping by the Parent/Guardian relationship type, "2 shifts plus one per additional student" as base 2 and additional 1, stocking at 3-to-1 as a sign-up/check-in source ratio, and kickoff as the period end. Rookies are the commitment's concern for its own pages; the requirement's exclusion makes the report row "Rookie".

Overall: all counting requirements: any `not_met` → Not eligible; any `pending` (signed up, not done) → Pending; else Eligible. Rows 2 and the "No meetings yet" case don't count against anyone.

### 13.3 Column-by-column check

| Report | Engine |
|---|---|
| Eligibility (overall, sort, score order) | Set overall; sort by overall then number of unmet then percent (set sort option, same order as `sorts["eligibility"]`) |
| 1747 Status "Registered / Not registered", tooltip | #1 detail "Has a GatherPack login" / "No GatherPack login with an email yet" |
| FIRST: Consent signed / Needs consent / Not registered, tooltip with sync date | #2 + #3. Needs consent = #2 met, #3 not met; the sync date is the badge description's line the sync writes, shown in #2/#3 detail |
| Concessions: Met / Signed up / Not yet / Missed, family detail "Family (names): n of m shifts" | #4: met / pending / not met; "Missed" from `due_on`; family text from commitment progress, names withheld per §10.1 |
| Outreach: Met / Signed up / Rookie / Not yet | #5 (exempt label "Rookie") |
| Attendance badge and lines "✓ Off-Season: n% of h (needs 10%)" | #6 `detail` lines, one per group; "Below minimum" label when not met; "No meetings yet" |
| Meetings, Hours at meetings, Attendance %, Extra hours; number filters | #6 measures `meetings`, `credited`, `percent`, `extra` (owner-only) |
| Academic Eligibility Yes/No | #7 |
| Tick filters per badge column; number min/max; name filter; counts | Report page §10.4 |
| Print layout, "Printed" line | Report page prints with the shared report print styles |
| Period buttons | "As of" picker (§9.1); the rules' dates |
| Admin alert box listing missing teams, badges, field, relationship type | Set page "Setup problems" from each kind's `problems` |

### 13.4 Other pages

| Page | Becomes |
|---|---|
| `safety-training-report.html.erb` (students missing a badge, with guardian contacts, sort by name/class) | A set "Safety training" with one `badge` requirement, the report's "Not met" filter saved as the default view, and an optional **Guardians' contacts** column that appears only when the viewer can already see those guardians (`visible_people.exists?` in the Page). Class sort needs a sort by team name pattern: stays a report option, not config |
| `outreach-report.html.erb` | The Outreach column of the set, plus the commitment's own page; the Page can be retired once that is checked |
| `academic-eligibility.html.erb` | Stays a Page: a bulk editor of one person field. The requirement reads the field |
| `clocked-in-report.html.erb` | Stays a Page: a live safety view, not a status |
| `attendance-report.html.erb` | The attendance requirement's per-person drill-down and measures; the Page stays until parity |

### 13.5 Viewer tiers

| Tier | Today | Configuration |
|---|---|---|
| Admins and managers of the top team | See all | Admin; manager of the set's team (`can_manage`, `leaders`) see everything. |
| Student Leadership team | Whole roster: name, overall, attendance columns; details only for themselves and wards | Grant: team "Team 1747 - Student Leadership", requirements `Attendance`, access `full`, minus owner-only extra hours. Everything else for themselves and wards comes from the `family` read level. |
| "Eligibility Report Viewer" badge | Same | Grant: that badge, same requirements and access. (Admin-assigned badge.) |
| Everyone else | Themselves and wards | `read_level` family; nothing in the query for anyone else |

Leaders see two sections as today ("Details for you and your wards", then "Team"); their sort and filters are limited to the columns they see.

### 13.6 Parity on staging

The Page's cells carry `data-filter` and `data-value` attributes (the cells built by `badge_cell`, line 393 of the Page). A script run by an admin session on staging fetches the Page and the set and compares, per person and per column: overall status, each requirement's status, the numbers. Differences are listed and each is either a bug or a recorded intentional change (leeway, a person field "blank" handling, "Pending" semantics, dates versus one period). The report passes when two weekly runs agree for every person.

## 14. Decisions

1. **Typed check kinds with small fixed forms; presets by copy.** No expression language, no generic query builder (§3).
2. **A layer above Commitments.** Requirements read commitment progress; Commitments stay the place for quotas, pooling and credit. No ratios or weekly rules in Commitments.
3. **`any_of` and `requirement_set` nest freely;** the only structural limit is no cycles. No NOT, no expression syntax.
4. **Results are stored, as a rebuildable cache,** refreshed by change, by clock and nightly, with a computed fallback on stale. Predicates use the stored rows.
5. **Evaluation is a pure function of data up to an as-of moment.** Cutoff dates fall out of that. Hooks never run inside user saves; the refresh job fires them.
6. **No check-in kind.** Event attendance for a status is a commitment of N. One way to count activity.
7. **Excuses are reasoned, audited, no self- or relative approval,** by managers of the set's team (and above) and admins only (product owner, 2026-11-06: not a current use case; kept for completeness). They can be for one meeting.
8. **Visibility is computed per viewer and omitted server-side;** two levels (status, full), `owner_only` measures, grants only by admin-assigned badge or team, commitment detail follows commitment visibility.
9. **Missing data is "not met" by default,** with the reason shown; a kind offers "blank counts as" only where blank is legitimately a value. "Nothing to judge yet" is `exempt` with a label, or `pending` under a minimum.
10. **No season, year or period concept.** A set's dates are its window; a requirement's dates default to it and can be overridden. Copying shifts dates and proposes replacements for a person to confirm (product owner, 2026-11-06).
11. **Attestation is a generic manual-check mechanism** and replaces badges used as manual flags. Confirming profile details is a form.
12. **Predicates are strict by default** (`met` or `exempt`); a caller may accept `pending`.
13. **Edits while running are allowed with a preview and an audit,** not versioned per date.
14. **Carry-over is part of building the rule, not the engine** (product owner, 2026-11-06). Each attendance rule is judged on its own or pooled with named others, as the organizer sets it; the kind has no built-in period or season default.
15. **Parity run before cutover** with the Page on staging; the Page stays the fallback until the first build weeks agree.
16. **Flag off by default; connectors per feature;** upstream files touched are routes, recurring jobs, schema, and two rule enums in connector branches.
17. **Generalist code.** Overall words, labels and exempt labels are set data; no "student", "travel" or "concession" in the code or in kind names. Dates of every kind (windows, cutoffs, rule dates) are data too; no month is assumed in code.
18. **"Record this list" ships in the first release** (product owner, 2026-11-06), in phase 3.
19. **Every check that looks at time takes a date or range,** defaulting to the set's window. "Signed on or after" needs no forms change. `form_complete` also honours the form's own expiry: expiry for a rule that belongs to the form, the requirement's date for one checklist's rule.
20. **Date housekeeping is configuration:** archive sets ended before a date, prune old results (§9.7).

## 15. Open questions

1. After how many held meetings should attendance start to be judged (it shows "Pending" before that)? Parity needs 0 first. (This could also be a setting on the rule rather than a decision.)
2. Should a student or guardian get an email when their overall goes from Met to Not met? Hooks make it possible; built in, it would be one more setting.

## 16. Phases

Phases are in dependency order. When each ships is the product owner's call.

| Phase | Lands | Side by side |
|---|---|---|
| 1 | `feature/requirements` core + `-attendance`; report, profile tab, excuses, preview; kinds `badge`, `has_login`, `team_member`, `age`, `any_of`, `requirement_set` | Tagged to Ditto as a preview build (rule: nobody touches production). Set built from §13 with attendance only. Compare attendance to the Page weekly. |
| 2 | `-commitments`, `-person-fields`, `-forms`, `attested`; full §13 set; grants | Whole Page compared per person (§13.6). Fix differences or record them. |
| 3 | `feature/mcp-requirements`, `feature/my-gatherpack-requirements`, hooks live, nightly job, "Record this list" | Two clean weekly parity runs |
| 4 | Ready for production; the set opens for viewers; the Page stays reachable and unlinked | The Page remains the source of record until the two agree on live data |
| 5 | Predicates (`-signups`, `-forms`), copy to next year, date housekeeping, `ledger_balance`, `hours` | — |

Backlog: close BL-003 as superseded when phase 1 opens; keep BL-002 on its own branch (it is an upstream bug independent of this).
