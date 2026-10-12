# Spec: Sign-up Sheets and Commitments

Status: rev. 10, 2026-10-12. Phases 1–5 are built and live in production since 2026-10-12 (`v0.0.0-hbr.17`); phase 6 and a commitments profile tab are in progress (§7). Decisions in §8 are settled or defaults; §9 lists open questions.

Rev. 10: status only. Phases 1–5 are live in production since 2026-10-12 (`v0.0.0-hbr.17`) on `feature/signups`, `feature/commitments` and `feature/signup-credit`; the completion badge is not built (decision 17). Phase 6 is in progress on `feature/signups-widget`, and a profile tab for commitments is in progress on `feature/profile-tabs` (BL-020) and `feature/commitments-profile-tab`. No decisions change.

Rev. 9: who owes can exclude holders of an exempt badge; check-ins at events that haven't started are planned; reports read commitment progress directly, and the completion badge is deferred (§4.1, §4.2, §4.6, decision 17). Phase 3 is built on `feature/commitments`; phases 4 and 5 are in progress.

Rev. 8: no extra people. Every place is one sign-up for one person in GatherPack; someone who isn't in GatherPack joins before they can work. Two people working together are two sign-ups, and the signer can make the second for the other person when the sheet allows it (decision 3).

Rev. 7: a position has one rule per kind, and badge and team rules are "any of" lists (§3.3). Phase 1 is built on `feature/signups`.

Rev. 6 scopes in item sign-ups (potluck and supply lists). A position is either people to work or items to bring, so one sheet can ask for both, as a lunch that needs food brought and servers does (§3.1, §3.5, decisions 15–16). This changes the Position concept, per §1.1.

Rev. 5 restructures the spec as a framework. HBR's sheets, production state, configuration and migration move to [`signups-hbr-rollout.md`](signups-hbr-rollout.md). Credit sources become an interface (§4.2), the seams between the layers are declared (§3.9, §4.8), grouping is "connected through a relationship type" instead of "shares a parent" (§4.4), a use case table (§1.2) is the test for future changes, and commitments gets its own organizer setting (§4.5) since it no longer depends on sign-ups. Renames: sign-up status `worked` → `fulfilled`, `counts_for` → `on_behalf_of` (with a meaning of its own, §3.2). The sign-up credit source moves to its own branch so commitments doesn't depend on sign-ups (§4.8, decision 2). Time TBA is dropped: events with no known time use 00:00–23:59 for now, and TBA and all-day events are BL-017 (decision 11).

This spec lives on `hbr/platform`, not on a feature branch. `feature/signups` is meant for upstream, so the feature branches themselves must not mention HBR.

## 1. Purpose

Two capabilities that organizations ask for together but that stand on their own:

- **Sign-up sheets.** People claim places at Events: a position, at an event, with a cap and rules about who may take it.
- **Commitments.** People (or groups of people) owe an amount of something, and activity earns credit toward it. Meeting a commitment grants a badge.

A sheet is useful with no commitment (a snack rota). A commitment is useful with no sheet (attend 5 outreach events, counted from check-ins). Together they cover "each family works 3 shifts".

### 1.1 The rule for this spec

Adding a use case is configuration, or an additive extension: a new eligibility rule kind (§3.3) or a new credit source kind (§4.2). If a use case needs the concepts in §2 to change shape, stop and revise the concepts first, with a rev. note saying why. The table in §1.2 is the record: add a row for each new use case, with its verdict.

### 1.2 Use cases

| Use case | Verdict | How |
|---|---|---|
| Staffing a stand at a series of games: positions with caps, a license badge, age bands, couples taking two places, working on another family's behalf | Fits | Positions, badge and age rules, one sign-up per person, on behalf of |
| Supervised work sessions where 3 sessions are worth 1 shift, optionally only up to a limit | Fits | Sign-up source with a ratio and an optional cap |
| A quota met by attending events, many of which have no sign-up | Fits | Check-in source |
| Household quotas (2 for the first child, 1 for each sibling) | Fits | Grouping and base + per-member amounts |
| Potluck or supply list ("bring 2 dozen cookies", "6 pizzas needed") | Fits | Item positions: a needed quantity in a unit; each sign-up brings part of it and says what |
| A meal that needs food brought and people to serve it | Fits | One sheet with item positions and people positions at the same events |
| "Bring a dessert", any number welcome | Fits | A position with no cap |
| Snack or carpool-driver rota, one person per week | Fits | One position, one slot per event |
| Competition volunteers across a multi-day event | Fits | One Event per day, or per event if it's one |
| Booth staffing in 2-hour shifts within one event | Additive, later | Optional start and end on a slot, so one event has several time windows per position. Until then, one position per window ("Booth 9–11"). |
| Per-person limits (at most 3 sign-ups on a sheet; one position per event) | Additive, later | Sheet-level rule kinds, checked like position rules |
| Waiting list for a full slot | Additive, later | Sign-up status `waiting`, promoted on cancel |
| Self-reported service hours, approved by an organizer | Additive, later | A "logged activity" source kind (§4.2), crediting in the commitment's unit |
| Credit for completing a form | Additive, later | A "badge held" source kind (§4.2) credits the form's completion badge. Gating a position on a form already works through a badge rule. |
| Carpools where drivers offer their own seats | Non-goal | Only organizers create slots |
| Sign-ups not tied to an Event (a season-long role) | Non-goal | Every slot is at an Event (§3.5) |
| Public sign-ups by people with no record | Non-goal | Decision 3 |
| Payments, swap marketplace | Non-goal | A person can drop a sign-up and someone else can take it; an organizer can move one. Nothing more. |

## 2. Concepts

| Concept | Layer | Meaning |
|---|---|---|
| Sheet | Sign-ups | A set of positions offered at a set of Events, with an audience, organizers and settings |
| Position | Sign-ups | Something a sheet asks for: people to work ("Cashier") or items to bring ("Main dish"), with a default cap and eligibility rules |
| Slot | Sign-ups | One position at one event. The thing people take. |
| Sign-up | Sign-ups | One person in a slot, possibly on behalf of someone else |
| Eligibility rule | Sign-ups | A test a person must pass to take a position |
| Organizer | Both | A person who runs a particular sheet or commitment without being an admin or team manager |
| Commitment | Commitments | Who owes, how much, over what period, and which sources count |
| Credit source | Commitments | A kind of activity that produces credit records, with a ratio and a cap |
| Credit record | Commitments | One unit of activity attributed to a person: quantity, planned or confirmed, and what it came from |
| Group | Commitments | People who owe together, formed through a relationship type |
| Completion badge | Commitments | The commitment's only output to the rest of GatherPack |

The badge as output matters: the Eligibility Report, the kiosk reminders widget and forms audiences all already work from badges, so a met commitment plugs into all of them with no new integration.

## 3. Sign-up sheets (`feature/signups`)

### 3.1 Model

- **Sheet.** Belongs to a team. Has a description (instructions shown at the top), a contact line, status (`draft`, `open`, `closed`, `archived`, same meanings as forms), and a list of Events.
- **Position.** Belongs to a sheet. Name, description, kind, default cap, eligibility rules (§3.3), and an optional question for each sign-up ("What are you bringing?", optionally required). Ordered. Two kinds:
  - **People**: the cap is places, one per person.
  - **Items**: the cap is a quantity in the position's unit ("pizzas", "dozen", "cases"). Each sign-up brings some of it.

  A position with no cap takes any number.
- **Slot.** One position at one event. Created for every position × event on the sheet. A slot can override the cap or be turned off for one event.
- **Sign-up.** Fields: `person` (who takes the place, or brings the items), `signed_up_by`, `on_behalf_of` (§3.2), `quantity` for item positions, `answer` (to the position's question), `note`, `status` (`active`, `cancelled`, `fulfilled`, `no_show`). For items, `fulfilled` reads "Brought" and `no_show` reads "Not brought".

A sign-up uses one place, or `quantity` units, of its slot. A slot is full when its active and fulfilled sign-ups use its whole cap.

### 3.2 Who a sign-up is for

Two people can differ from the signer:

- **Who takes the place.** Usually the signer. The choices are the signer plus people related to them through the sheet's **sign up others** relationship types (none by default). A guardian signing up their child is this.
- **On behalf of.** Usually the person who takes the place. Someone else when the place is taken for them: a parent works a shift for their child, or a neighbor covers for another family. The sheet's **on behalf of** setting picks the choices: `nobody else` (default), `related people` (through the same relationship types), or `anyone the sheet is open to`.

On behalf of has a meaning in this layer, independent of commitments: the sign-up appears in that person's **My sign-ups** ("Taken for you by …"), they get its notices, and the roster shows it. Commitments additionally credit it (§4.3).

### 3.3 Eligibility rules

A position has a list of rules, all of which must pass. Rule kinds in v1:

| Kind | Settings | Passes when |
|---|---|---|
| Badge | One or more badges | The person holds any of them |
| Age | Minimum and/or maximum | The person's age on the event date is in range. No birthday on file fails. |
| Team | One or more teams | The person is in any of them or a team below one |

A position has at most one rule of each kind, and a rule's list means any of it. "A person must pass every rule; within a rule, any one ticked badge or team is enough." The setup screen edits the existing rule of a kind rather than adding a second, so it can't build a combination nobody passes (rev. 7: two team rules for Parents and Friends were ANDed on staging).

Rules apply to **who takes the place**, not the signer. A person who fails sees why ("Needs the Alcohol License badge") and can't take the slot. Organizers can place anyone; the roster flags a placement that fails a rule (decision 4). Organizers see pass or fail, never the underlying data (a birthday, for example).

Adding a rule kind is additive: a kind, its settings, a check, and a reason message. Sheet-level kinds (per-person limits, §1.2) use the same shape.

Forms connect through the badge rule. A position can't require a form; a form grants a badge on completion and the position requires the badge. This keeps `feature/signups` independent of `feature/forms` and is how the rest of GatherPack already gates things.

### 3.4 Audience and visibility

A sheet has a team and audience rules in the same shape as forms (`form_audience_rules`: include and exclude teams or badges), so a sheet owned by a parent team can be open to two of its subteams and not a third. A **see names** setting picks who sees names on the sheet page: by default everyone who can sign up (as paper and SignUpGenius sheets do). Organizers see notes, the roster and on behalf of. The roster shows names only, never contact details beyond what the viewer could already see.

### 3.5 Events

Sheets staff Events. Every slot is at an Event; sign-ups with no event are a non-goal (§1.2).

- **Add dates** on a sheet creates Events in bulk for the sheet's team: a list of dates, each with start and end time, name, location, and one event type chosen for the sheet. It can also attach existing Events.
- **Unknown times.** `events.start_time` is required. A date whose time isn't known yet is entered as 00:00–23:59 and given its real time later; changing it notifies everyone signed up (§3.7). Sign-ups has no TBA of its own (decision 11).
- **Event page panel.** The event page shows a Sign-ups panel: positions, places or quantities filled, and names (to people allowed to see them).
- **Check-in means showed up.** When someone checks in to an event, their active sign-ups to people positions at that event become `fulfilled`. After the event ends, an organizer can mark any sign-up `no_show`. A check-in never creates a sign-up.
- **Items are marked by an organizer.** Bringing food doesn't mean staying, so a check-in doesn't fulfil item sign-ups. The roster has **Mark all brought** for an event's items, then the organizer marks the exceptions Not brought (decision 16) Mark all brought skips the organizer's own and their relatives' sign-ups, which another organizer marks (§3.6).

### 3.6 Organizers

Sheets are run by volunteers, not admins or team managers. Team management is the wrong tool: in upstream it grants editing of the team's people, memberships and events (`EventPolicy`, `Team#all_managers`).

**Organizer grants.** A setting, `signups_organizers`: a list of pairs, each an admin-assigned badge and a highest team. Holders of a listed badge may create sheets for teams within that pair's reach, using the same rule as `Form.creator_team_ids`: teams they belong to (and those above) up to the highest team, plus teams below their own. Several pairs give the union. Admins and managers of a sheet's team can always create and run sheets.

This is the same pattern as forms' `forms_creator_badge` and `forms_creator_highest_team`, generalized to a list. It is a platform pattern (delegated organizer for a capability, capped at a team), not a sign-ups invention; see §9 on sharing it.

**A sheet's organizers.** Each sheet has a list of organizers, starting with its creator. An organizer can add others who hold a granting badge. Organizers have full control of that sheet only: settings, positions, dates, the roster, fulfilled and no-show, placing people (including rule overrides), and notices. They see the people on that sheet's roster and nothing more of their records.

**No approving yourself.** An organizer can't, for themselves or anyone related to them (any relationship type): mark a sign-up fulfilled or no-show, place them against a rule, or move a sign-up to or from them. Another organizer, a team manager or an admin has to. The page says why the button is missing. Ordinary sign-up and cancel are unaffected.

**Events made by a sheet.** Creating an Event needs management of its team (`EventPolicy#create?`). Add dates creates Events itself, authorized by the sheet's policy. Organizers can change the time, place and name of events their sheet created, from the sheet, and nothing else. Events a manager made and attached stay editable only by managers. No change to `event_policy.rb`.

**Audit.** Every organizer change goes through `has_paper_trail`.

### 3.7 Notices

Reuse the mailer and the forms reminders pattern: confirmation on sign-up (to the person, the signer and on-behalf-of person), a reminder a set number of days before (sheet setting, default 2), and a notice when an event's time or date changes or an organizer cancels or moves a sign-up. Organizers can message everyone signed up for a date; the email goes out without showing addresses to the organizer.

### 3.8 Experiences

**Member: take a place.**
1. **Sheets** (under Events in the menu) lists open sheets the person can sign up for, with their own sign-ups first.
2. The **sheet page** lists dates; each date lists positions with "n of m filled" (people) or "4 of 6 pizzas" (items), names and answers ("Cheese, 2") if visible, and **Sign up**. A position the person can't take says why instead. **My sign-ups** is at the top, with **Change** and **Cancel**.
3. The **sign up dialog** asks who takes the place (if the sheet allows others), on behalf of (if allowed), then how many, up to what's still needed (item positions), the position's question if it has one, and a note. Other features can add hints here (§3.9).
4. Members can cancel until the sheet's cut-off (default: the event's start). After that only organizers can.

**Organizer: run a sheet.**
1. Create the sheet: team, audience, description, contact.
2. Add positions and their rules, then Add dates. Slots appear for every position × date; adjust caps or turn slots off in a grid.
3. Open it. Watch the **roster**: one table per sheet (date, position, person, quantity, answer, on behalf of, note, status) with filters and print (shared report print CSS). Add, move and cancel sign-ups; send notices.
4. After each event: check-ins fulfil people sign-ups automatically; mark absences no-show; Mark all brought for items, then mark what didn't come.
5. Close, then archive.

### 3.9 Seams this layer offers

The sign-ups layer knows nothing about commitments. Other features attach through:

- **Hooks.** Every model includes `CanBeHooked`. Named events `signups - fulfilled` and `signups - cancelled`, like `form_responses - completed`.
- **Notifications.** `signup_changed.gatherpack` (sign-up created, status changed, moved, cancelled) and `signup_sheet_changed.gatherpack` (positions, slots or events changed), following `person_field_changed.gatherpack`. Commitments recompute from these.
- **View extensions.** A small registry in the sign-ups layer, `Signups.extensions`, with two slots: panels on the sheet page (rendered under My sign-ups, given the sheet and viewer), and a hint next to each on-behalf-of choice in the sign up dialog (given the sheet and candidate person, returns short text). Upstream gets a generic extension point; commitments fills it without editing sign-up views. Confirm against GatherPack's existing patterns (`GatherPack::Features`) before building and match them.

### 3.10 Data

New tables (upstream naming):

| Table | Columns |
|---|---|
| `signup_sheets` | `team_id`, `title`, `description`, `contact`, `status`, `event_type_id`, `names_permission`, `others_relationship_type_ids` (array), `on_behalf_of_mode`, `cancel_cutoff_hours`, `reminder_days`, `created_by_id` |
| `signup_sheet_organizers` | `signup_sheet_id`, `person_id` |
| `signup_audience_rules` | Same columns as `form_audience_rules`, keyed to `signup_sheet_id`. This branch doesn't depend on forms, so it has its own table. |
| `signup_sheet_events` | `signup_sheet_id`, `event_id`, `created_by_sheet` |
| `signup_positions` | `signup_sheet_id`, `name`, `description`, `kind` (`people`, `items`), `unit`, `capacity` (null = no cap), `question`, `question_required`, `position` |
| `signup_position_rules` | `signup_position_id`, `kind` (`badge`, `age`, `team`; one per position), `badge_ids` (array), `min_age`, `max_age`, `team_ids` (array) |
| `signup_slots` | `signup_position_id`, `event_id`, `capacity` (null = position default), `disabled` |
| `signups` | `signup_slot_id`, `person_id`, `signed_up_by_id`, `on_behalf_of_id`, `quantity`, `answer`, `note`, `status` |

Slot fill is checked inside a row lock on the slot, so two people can't take the last place at once.

Upstream files touched (estimate): `config/routes.rb`, `config/initializers/features.rb` (register), `lib/settings.rb` (`signups_organizers`), `app/models/hook.rb` (catalog), `app/views/events/show.html.erb` (panel render), `app/models/event.rb` (association), `db/schema.rb`. Check-in → fulfilled subscribes from an initializer (decision 7), not by editing `checkin.rb`.

## 4. Commitments (`feature/commitments`)

### 4.1 Model

- **Commitment.** Belongs to a team. Has:
  - **Who owes**: a team, optionally narrowed by a badge, minus holders of an optional **exempt badge** (a season's rookies, for example).
  - **Amount**: a base amount, and optionally a per-additional-member amount for groups (§4.4).
  - **Unit**: a display label ("shifts", "events", "hours"). Quantities are whole numbers in this unit.
  - **Period**: start and end dates. Only activity in the period counts.
  - **Counts when**: `planned` or `confirmed`. Pages always show both ("2 confirmed, 1 planned, 2 owed"); this setting picks which completes the commitment.
  - **Completion badge** (optional, deferred): granted when met, removed when it stops being met. Not built; reports read progress instead (decision 17).
  - **Sources**: an ordered list (§4.2).
- **Adjustment.** Manual credit or debit for a person, with a reason. Shown separately in the breakdown.

### 4.2 Credit sources

A source kind is the extension point of this layer. Each kind provides:

| Part | What it does |
|---|---|
| Subject | What a source of this kind points at (a sheet or position, an event type, …), chosen when the source is added |
| Records | For a commitment, its period and its owing people: credit records, each with person, quantity, state (`planned` or `confirmed`), date, a **dedupe key** (usually the event), and a label and link for the breakdown |
| How to earn | A line and link for a person's commitment page ("Sign up on Snack Rota", "Check in at any Outreach event", with upcoming ones) |
| Watches | The notifications that should trigger a recompute |
| Who may add it | Which organizers may add a source with this subject |

Every source then has the same settings, applied by the commitment, not the kind: a ratio (`per` records' quantity earns `credits`) and an optional `max_credits` per person or group. A source's credit is `floor(quantity × credits / per)`, capped. Ratios are two integers so 3 sessions make exactly 1 credit. Partial progress shows as "2 of 3 toward 1".

**Dedupe.** Within a commitment, records with the same person and dedupe key count once, from the first source in the commitment's order. So a sheet source listed above a check-in source for the same events counts the sign-up, and the check-in adds nothing.

Kinds in v1:

| Kind | Branch | Subject | Records |
|---|---|---|---|
| Check-ins | `feature/commitments` | An event type, on events of the commitment's team or below | One per check-in, quantity 1, to the person checked in: confirmed once the event has started, planned before. Dedupe key: the event. |
| Sign-ups | `feature/signup-credit` | A sheet, or one position on it | One per sign-up, to the on-behalf-of person. Quantity: 1 for people positions, and 1 for item positions, since bringing 3 pizzas is one contribution. Active is planned, fulfilled is confirmed; cancelled and no-show produce nothing. Dedupe key: the event. |

Adjustments aren't a source kind; they're added after sources and don't count toward source caps.

Later kinds are additive: **logged activity** (a person reports activity with a date and quantity, an organizer approves it; approved is confirmed), **badge held** (holding a badge is worth a fixed credit). None needs a change to commitments.

### 4.3 Attribution

Each kind decides whose credit a record is, and says so in the table above. Commitments doesn't second-guess it. The only cross-kind rules are dedupe (§4.2) and grouping (§4.4).

### 4.4 Groups

A commitment can be owed by groups instead of individuals. It names a relationship type; owing people who share a related person (one step through someone outside the owing population, such as a parent) are one group, and so are chains of those through owing people. With a parent–child type that makes siblings and half-siblings one group, but not cousins through a recorded grandparent; with a household type it makes households. A person with no connection is a group of one.

A group owes the base amount for its first member plus the per-additional amount for each other member. Credits of everyone in the group pool, and source caps apply to the group. The completion badge goes to every member of a group that has met its amount.

### 4.5 Organizers

Same pattern as sheets (§3.6): holders of a badge listed in `commitments_organizers` (badge → highest team pairs; same shape as `signups_organizers`, separate setting) create commitments within their reach, and each commitment has its own organizers list. Admins and managers of the commitment's team can do the same.

Organizers see **progress only** for everyone the commitment covers (owed, confirmed, planned, remaining, breakdown by source), nothing else from their records. Each source kind says which subjects an organizer may add (a sheet they also organize; an event type, for events within their reach). The completion badge must be admin-assigned, so organizers couldn't otherwise grant it, which keeps it trustworthy on reports. Organizers record adjustments with a reason; no approving yourself or your relatives applies, as in §3.6.

### 4.6 Experiences

**Person who owes: what do I owe and how do I earn it.** A **My commitments** section on the person's profile (and, through §3.9, on any sheet that feeds one): each commitment with owed, confirmed, planned and remaining, the breakdown, and each source's **how to earn** line. Parents see it for people they're related to through the commitment's group relationship type.

**Organizer: track and close out.**
1. Create the commitment: who owes, amount, unit, period, grouping, counts when, completion badge.
2. Add sources in order, each with its ratio and cap.
3. The **commitment page** has one row per person or group: members, owed, confirmed, planned, remaining, breakdown. Filters: met, not met, nothing planned. Print. **Message people with open commitments** sends without showing addresses.
4. Record adjustments for edge cases.

**Signing up for someone who owes.** When a sheet feeds a commitment, the on-behalf-of choices in the sign up dialog show each person's remaining amount, through the hint slot (§3.9).

### 4.7 Data

| Table | Columns |
|---|---|
| `commitments` | `team_id`, `title`, `description`, `owing_team_id`, `owing_badge_id`, `base_amount`, `additional_amount`, `unit`, `group_relationship_type_id`, `counts_when`, `completion_badge_id`, `starts_on`, `ends_on`, `created_by_id` |
| `commitment_organizers` | `commitment_id`, `person_id` |
| `commitment_sources` | `commitment_id`, `kind`, `subject_type`, `subject_id` (polymorphic: `EventType`, `SignupSheet`, `SignupPosition`, …), `per`, `credits`, `max_credits`, `position` |
| `commitment_adjustments` | `commitment_id`, `person_id`, `credits`, `reason`, `created_by_id` |

Kinds register in an initializer (`Commitments.register_source(kind, klass)`). A source whose kind isn't registered (its branch isn't in the build) shows as unavailable and counts nothing.

Progress is computed, not stored. A job recomputes badge grants when a watched notification fires, when a relationship or badge assignment changes, and nightly.

### 4.8 Branches

- `feature/commitments` from `upstream/main`: commitments, groups, adjustments, the check-in kind. Doesn't depend on sign-ups.
- `feature/signup-credit`, depending on both: the sign-up kind and the dialog hint. Small, and the only place that knows both layers.

## 5. Hooks

Every new model includes `CanBeHooked`. Add to `Hook.catalog`:

- `signup_sheets`, `signup_positions`, `signup_slots`, `signups`, plus `signups - fulfilled` and `signups - cancelled`.
- `commitments`, `commitment_sources`, `commitment_adjustments`, plus `commitments - met` and `commitments - unmet` (per person, when completion changes).

The hardcoded catalog is BL-014's drift problem; these follow the current pattern and move with whatever BL-014 decides.

## 6. Sample data and tests

- `fork/sample_data/features/signups.rb`: a Northwind sheet with a few events, positions with a badge rule and an age rule, a couple as two sign-ups, one on behalf of another person, one full slot, one fulfilled by check-in, one event at 00:00–23:59 whose time is set later. A lunch with item positions (one capped in a unit, one uncapped, one with a required question) and a people position for servers, with items brought and not brought.
- `fork/sample_data/features/commitments.rb`: a grouped commitment with a capped check-in source and an adjustment; groups met, partial and empty. A per-person commitment counted from check-ins.
- `fork/sample_data/features/signup-credit.rb`: a sheet feeding the grouped commitment above a check-in source, showing dedupe.
- Model tests: slot fill under concurrency, for places and for quantities; each rule kind on the event date; ratio and cap arithmetic; dedupe across sources; group formation (direct, chain, single); badge grant and removal; an unregistered kind. System test for the sign up dialog.
- All three branches go in `fork/catalog.yml` and `FORK.md`.

## 7. Phases

1. **Sheets and sign-ups**: §3.1–3.4, 3.6, 3.8. *Built* (`feature/signups`), including item positions.
2. **Events integration**: Add dates, event panel, check-in fulfils, notices, view extensions. *Built* (`feature/signups`), including reminders.
3. **Commitments core**: §4.1–4.3, 4.5–4.7 with the check-in kind and adjustments, without groups. Can ship before or without sheets. *Built* (`feature/commitments`), with the progress API (decision 17).
4. **Groups and badges**: §4.4, completion badge. *Built* (`feature/commitments`): groups and the exempt badge. The completion badge is deliberately not built (decision 17).
5. **Sign-up credit**: `feature/signup-credit`. *Built*: sign-ups as a credit source and the on-behalf-of hints.
6. **Widget** (separate branch, depends on `feature/widgets`): "My sign-ups and commitments". *In progress* on `feature/signups-widget`: a summary partial an admin places as a one-line widget.

Phases 1–5 are live in production since 2026-10-12 (`v0.0.0-hbr.17`). Also *in progress*: a commitments tab on the person profile (§4.6), through a generic profile-tab seam on `feature/profile-tabs` (BL-020) and `feature/commitments-profile-tab`.

## 8. Decisions

Settled 2026-10-11 unless marked otherwise. Decisions about one organization's setup belong in its rollout doc, not here.

1. **Two layers.** `feature/signups` from `upstream/main`, upstreamable, upstream naming, no `Hbr::`.
2. **Three branches.** Commitments doesn't depend on sign-ups; `feature/signup-credit` joins them (§4.8). Replaces "commitments depends on signups".
3. **No public sign-ups, no extra people.** Only people in GatherPack take places, one sign-up each, so rules and badges are checked for everyone who works. Someone not in GatherPack joins first. A person signs up someone else through the sheet's sign up others setting (§3.2) or an organizer does it (rev. 8; replaces extra people and named outsiders).
4. **Rules block members, organizers override**, with the roster flagging the override.
5. **On behalf of** is a sign-up field with its own meaning (§3.2); commitments credit it.
6. **Paired positions** (default). When one role must also take a place in another, the instruction goes in the position description and the person signs up twice. Add an "also takes a place in" option only if this proves a problem.
7. **Check-in callback from an initializer** (default), not an edit to upstream `checkin.rb`.
8. *(Removed in rev. 8: there are no extra people.)*
9. **Organizers are specific people with a badge**, never team managers created for the purpose.
10. **Organizers see only their own sheets' and commitments' people**: names, pass/fail on rules, and progress. No profiles, birthdays or contact details.
11. **No Time TBA in sign-ups.** Events with no known time are entered as 00:00–23:59 for now. TBA and all-day events belong to Events, not sign-ups, and are backlog item BL-017.
12. **Count, don't time** (default). Credit is per record, not per hour. Time-based credit comes with a logged-activity kind or slot times (§1.2), both additive.
13. **Check-in means showed up.** Credit from a sign-up comes from the sign-up; a check-in only fulfils it.
14. **No approving yourself or your relatives**: fulfilled and no-show, rule overrides, moves, adjustments.
15. **Items and people on one sheet.** A position's kind decides whether its cap counts people or a quantity. Rules, on behalf of, notices and organizers work the same for both.
16. **Items are marked brought by an organizer** (default), with Mark all brought per event. A setting to treat items as brought once the event has passed can be added if marking proves a chore.
17. **Reports read progress, not badges.** `Commitment#progress_for(person)` (the person's group, or them alone: owed, confirmed, planned, remaining, met, breakdown) is the supported way for reports and other features to ask; `covers?` says whether someone owes at all. A completion badge stays optional and isn't built.

## 9. Open questions

1. **Share the organizer-grant pattern with forms?** Forms has one badge and one highest team; sheets and commitments have lists. A shared `OrganizerGrant` (capability, badge, highest team) would serve all three and the next feature. Default for now: separate settings of the same shape, so forms is untouched.
2. **Slot times in v1?** Default no (§1.2: one position per window until it's needed). Adding them later is a nullable start and end on slots and a grid change.
3. **Per-person limits in v1?** Default no.
4. **Dedupe when the first source's record is only planned.** Today the first source in order wins for a person and event, even if its record is planned and a later source has a confirmed one (an item sign-up not yet marked brought, plus a check-in at the same event). Prefer a confirmed record over a planned one for the same key? Also, a person's two sign-ups at one event (a shift and a dish) count once, because the key is the event. Raised in the phase 5 review, 2026-10-11; doesn't affect HBR's concessions or outreach.
