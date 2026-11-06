# Spec: Membership Intake (joining and rejoining a team)

Status: draft rev. 1, 2026-11-05. Nothing is built. Code facts below were checked at integration `49609326`. Decisions in §18 are defaults the product owner can overturn; §19 lists the open questions.

This spec lives on `hbr/platform`, not on a feature branch. The generic branches are meant for upstream, so they must not mention HBR. HBR's setup is in Appendix A and nowhere else.

A companion spec, `requirements-spec.md`, designs the rules engine ("requirement sets") that this spec consumes. §13 states exactly what intake needs from it. This spec does not design that engine.

## 1. Purpose

A person can join a team, or join it again for a new season, from inside GatherPack, with nobody hand-creating records. Two ways in share one flow:

- **Kiosk.** A manager is signed in on a device at a callout or open house. People in the room give a few facts and finish at home.
- **Self-service.** A public link for a season that anyone with the link can use, and that an organizer can open and close.

What the flow must prevent, all seen in the last registration: guardians not linked, people with no login, students missing the class team that decides who is new, duplicate placeholders, a typo'd email, a student listed twice.

### 1.1 The rule for this spec

Intake is configuration over footings that exist. A new case is a new way to join (§3), a new placement rule (§8), or a new check in the joining checklist (§13). If a case needs the concepts in §3 to change shape, stop and revise them first, with a rev. note saying why. The table in §1.2 is the record: add a row for each new use case, with its verdict.

GatherPack code has no words like student, parent or rookie. Those are names an organization gives to teams, badges and ways to join.

### 1.2 Use cases

| Use case | Verdict | How |
|---|---|---|
| A guardian registers one or more children, and themselves | Fits | One household entry, several people (§6.1) |
| A young person registers and names a guardian | Fits | Entry with a guardian email; the guardian confirms by email (§6.2) |
| An adult joins as a mentor or volunteer | Fits | A way to join with its own questions, target team and checklist (§3) |
| Returning members rejoin each season, pre-filled, re-confirming info and re-signing | Fits | Renewal path of the same registration (§9) |
| A sibling or returning family is matched, not duplicated | Fits | Matching on login email, then manager review (§6.3) |
| Registering in the room on a shared device | Fits | Kiosk mode (§5) |
| Applicant waits for FIRST registration or consent, tracked but not automated | Fits | A checklist item fed by a badge the sync script grants (§9.3) |
| Dues, background checks, training | Fits | Checklist items: a badge held, or a commitment met (§9.3) |
| Joining a team that needs no approval | Fits | The registration skips approval; the checklist still runs (§10.4) |
| One registration offering several teams (a robotics team and a sub-team) | Fits | A way to join lists several target teams, "any of" (§3) |
| Different organizations or teams in one install | Fits | Each registration belongs to a team; its managers run it |
| Alumni, sponsors, supporters joining a list | Fits | A way to join whose target team is theirs and whose checklist is empty |
| Capacity limits and a waiting list | Additive, later | A cap on a way to join; entries past it get status `waitlisted`, promoted by hand first (§10.5) |
| Mid-season joiners | Fits | The registration stays open; the season dates only decide what "this season" means (§9.1) |
| Moving between teams (a student to a different sub-team) | Non-goal for v1 | Managers use the existing memberships screens; transfers don't need intake |
| A student reaching the guardianship age mid-season | Fits | Guardian rules go by the existing age limit at the time they are checked (§7.4) |
| Automated filing on FIRST's own site | Non-goal | The site can't be automated; intake links and tracks only (§9.3) |
| Paying dues online | Non-goal | A checklist item can be met by a ledger or commitment; payment collection is another feature |
| Re-using one registration link across seasons | Non-goal | One registration per season; the next is a copy (§3) |
| Public registration without any email | Non-goal | Verification needs an email (§7.1). In-room people without one use the staff path. |
| Merging people already duplicated | Additive, later | A separate admin tool, `feature/person-merge` (§6.4) |

## 2. What exists today

Verified at integration `49609326`. Everything in §2.1 is reused as is.

### 2.1 Footings reused

| Footing | Where | Use |
|---|---|---|
| `MembershipApplication`: pending, approved, denied; `message`, `reviewer_notes`; `approve!` creates a `Membership` and marks approved; `deny!` | `app/models/membership_application.rb:10` (enum), `:22` (`approve!`), `:29` (`deny!`) | The approval step. Intake adds to it, never replaces it. |
| Only teams with `join_permission: requires_approval` accept an application | `membership_application.rb:18` and `:43` (validation); `team.rb:20` (enum) | Targets of an approval-gated registration must use this join permission. |
| One pending application per person and team | Unique index, `db/schema.rb:604`; validation `membership_application.rb:14` | A renewal of an existing member is not an application (§9.2). |
| Policy: applicant must be a person who is not on the team and has no pending application; managers and admins decide | `app/policies/membership_application_policy.rb:21` (`create?`), `:28` (`update?`) | Unchanged. Intake creates applications through the model, as the applicant. |
| Managers' list and decision | `app/controllers/membership_applications_controller.rb:35` (`update`); route `config/routes.rb:29` (team) and `:89` (person) | The approval screen gains the checklist column (§10). |
| `approve!` doesn't notify, and the application has no reason field on deny | `membership_application.rb:22-30` | Intake adds notices (§12) and a deny reason. |
| MCP already lists and decides applications | `app/models/mcp/tools/decide_membership_application.rb`, `list_membership_applications.rb`, `withdraw_membership_application.rb` | Parity work is mostly extending these (§15). |
| Devise: database auth, recoverable, no `confirmable`; `config.reconfirmable = true` is inert without it; `paranoid` is off | `app/models/user.rb:10`; `config/initializers/devise.rb:93,160` | Intake does its own email verification (§7.1). It doesn't turn Devise's modules on. |
| `local_signup` and `oauth_signup` settings; registrations route skipped when off | `lib/settings.rb:130,132`; `config/routes.rb:280-284` | Left alone. Intake works with `local_signup` off. |
| `People#create` makes a `User` with a generated password when an email is given | `app/controllers/people_controller.rb:44-49` | The pattern intake follows: a known email gets a login. |
| `Person#email` is a plain accessor; the email is stored only on `User` | `app/models/person.rb:24`; `db/schema.rb:1164` (`users.email`, unique) | A person with no login has no stored email. An entry must hold the email until the `User` exists (§7.2). |
| Guardianship: relationship types (`none`/`minor`/`consented`), `Guardianship Age Limit` | `app/models/relationship.rb:15-33`; `person.rb:115-136`; `lib/settings.rb:150` | Guardian links and age rules (§7.4). |
| Forms: audience rules, signatures, guardian signatures (`guardian_if_minor` goes by age, 18 when no limit is set), content versions, reconfirmation, completion badge, "updates profile" questions that start from the profile | `app/models/form.rb:268-283`; `form_response.rb:51,69-73,117-127`; `form_access.rb:104-120` | The signing and "confirm your info" steps (§9). |
| Form audience rules target a team, a badge or one person | `app/models/form_audience_rule.rb:10-16` | Missing: applicants are in no team (gap 2 in §2.3). |
| Person fields with read and write levels | `app/models/person_field*.rb`; `AudienceLevels` (`app/models/audience_levels.rb`) | Grad year, grade, school and the like are person fields. |
| Time kiosk: manager's signed-in device, `Settings kiosk users team`, card tokens, rate limit, return-to-welcome | `app/controllers/time_kiosk_controller.rb:3-8,124-129`; `lib/settings.rb:144-146`; `app/models/token.rb` | Patterns for kiosk mode (§5). |
| Search-and-add duplicate matching | `app/views/shared/_add_panel.html.erb`; `app/models/mcp/tools/find_duplicate_people.rb` (name, then login email, in `policy_scope(Person)`) | Matching ideas; the tool's scoping shows why matching must be server side (§6.3). |
| Sign-ups on behalf of | `signups-spec.md` §3.2 | A guardian acting for a ward; the same pattern for the checklist (§9.4). |
| Audit trail | `has_paper_trail versions: { class_name: "AuditLog" }` on the models; whodunnit `true_user&.id` at `application_controller.rb:82` | Intake models carry it. Public requests need their own whodunnit (§11.6). |
| Jobs and mail | `app/jobs/send_email_job.rb`; `config/recurring.yml`; `FormScheduleJob` | Notices (§12), expiry and cleanup. |
| Hooks | `CanBeHooked`; `config/initializers/hook_events.rb`; `GatherPack::HookCatalog` | §14. |
| Rate limits | Rails `rate_limit`: `time_kiosk_controller.rb:7`, `mcp_controller.rb:12`; production cache is Solid Cache (`config/environments/production.rb:68`) | The mechanism for §11. |

### 2.2 What is not there

- **No season.** `grep -i season` finds nothing in models, schema or settings except two unrelated words in sign-up files. Memberships have no dates (`db/schema.rb:609`). Nothing records that a person belongs "for 2027".
- **No public registration other than Devise's.** The Devise form creates a `User` and a blank `Person` with no verification and no team.
- **No person merge.** There is no tool to combine two people.
- **No unverified state.** An email is accepted as typed. Nothing finds out it was wrong until a message bounces.
- **No applicant concept.** An applicant is a `Person` with no teams and a pending `MembershipApplication`.

### 2.3 Gaps in forms and applications this spec has to fill

1. **A form can't expire at a season boundary.** `reconfirm_from_version` (`form.rb:278-281`) reconfirms by content version, for everyone, when someone publishes with "ask them to sign again". It works for one season: bump it on May 1. It is a manual step per form, it hits alumni and non-returners too, and a form re-sent that way takes away the completion badge (`form_response.rb:124-125`). The fix is small and additive: a form can renew each season (§9.1).
2. **Applicants can't be in a form's audience.** An audience is teams, badges or named people (`form_audience_rule.rb:10-16`). Someone who has only applied is in none. Intake needs an audience rule that means "has a pending application to this team" (§13).
3. **An application has no checklist.** The manager sees a message and approves blind.
4. **An application has no source or season.** Nothing says it came from a link, a kiosk or a person's own request, or which season it was for.
5. **Approval does one thing.** `approve!` adds one membership. Class teams, parent teams and the first-year badge are separate steps someone must remember. This is the "missing class team" failure.

## 3. Concepts

| Concept | Meaning |
|---|---|
| Registration | An offer to join a team for one season: a public link, open and close dates, a kiosk switch, one or more ways to join. One per season. Belongs to a team; that team's managers run it. |
| Way to join | One option under a registration: a name shown to people, the team(s) it applies to, whether approval is needed, a form of questions, placement rules (§8), a joining checklist (a requirement set), and whether a guardian is needed. Examples: "Join as a student", "Join as a mentor", "Family contact". |
| Entry | One in-progress registration by one household. Holds a few facts and a verification token before any person records exist (§7.2). Expires if not verified. |
| Household | The people on one entry: the one who verified, and anyone they add (children, a guardian). |
| Applicant | A person with a pending application from a registration. Not a stored status; it is computed from the application. |
| Placement rule | When an application is approved, also join other teams, grant a badge, or both, depending on facts about the person (§8). |
| Joining checklist | The requirement set "Join <team> for <season>" (companion spec). Intake shows its status and never defines its checks. |
| Season | A named date range, `starts_on` to `ends_on`. See §9.1 for what intake assumes. |
| Renewal | A returning member's path through the same registration: no approval, same checklist. |

Rules of thumb:

- A **registration** is per season. The next season is "Copy registration", which copies ways to join and the checklist and shifts the dates. The old link then says "Registration for 2027 has closed. Registration for 2028 opens May 1." (the old registration stores a pointer, §16.2).
- A **way to join** is where every organization-specific rule lives. The generic code never names the people it serves.
- Several ways may be offered on one screen. A screen that lets someone choose more than one must say so: "Choose any that apply." Each choice makes its own application.

## 4. Lifecycle

```
interest -> entry -> verified -> application -> checklist -> decision -> member
                                                                 \-> denied
member (last season) -> renewal prompt -> checklist (re-confirm, re-sign) -> renewed
```

| Stage | What happens | Who sees it |
|---|---|---|
| Interest | Someone hears about the team and opens the link, or is handed the kiosk. | Anyone with the link |
| Entry | A few facts and an email are collected. Nothing is stored as a person yet (self-service) or only a held row (kiosk). | The person |
| Verified | The person opens the link in their email. People, login and guardian links are created. | The person |
| Application | One `MembershipApplication` per person per target team, source recorded. | The person and the team's managers |
| Checklist | The person (or their guardian) works through forms, signatures, info confirmation and anything else the checklist lists. | The person, their guardian, the managers |
| Decision | A manager approves or denies. Approval adds memberships through placement rules (§8). | Managers |
| Member | The person is on the team. The checklist keeps running until Met; approval does not wait for it unless the way to join says so (§10.2). | Everyone as today |
| Renewal | Next season, a returning member sees "Renew for 2028". The same checklist, with every season-bound check Pending again. | The person and managers |

Approval and the checklist are independent: a team can approve first and finish forms after, or require Met before the Approve button works. That is a per-way-to-join choice, default "checklist doesn't gate approval" (§10.2), because managers often meet people before forms are done.

## 5. Two modes, one flow

Both modes run the same `Intake::Flow`: choose a way to join, give the facts, name the household, create an entry, verify, continue at home. They differ in who can reach them and how much they show.

| | Kiosk | Self-service |
|---|---|---|
| Address | `/join/<slug>/kiosk` | `/join/<slug>` |
| Who can open it | A signed-in admin, or a manager of the registration's team who is on the kiosk accounts team (§5.2) | Anyone with the link, while the registration is open |
| Why less restricted | A manager is in the room, so a person's presence is some assurance | None; every step is defended (§11) |
| Records created | Person, login and application right away, marked "not yet verified" | Nothing but an entry until the email is verified |
| What it asks | Name, grade or graduation year, own email, guardian email (when a guardian is needed) | Name, email, way to join; the rest after verification |
| What it never shows | Any existing record, matches, medical or private fields, forms, signatures, anyone's birthday or phone | Matches, whether an email has an account, any other person's data |
| Signing | Never. Signatures and medical data are never asked on a shared screen. | After verification, in the person's own session |
| Verification | An invitation email to finish at home; opening it verifies and sets a password | Opening the verification link creates the records |
| Reset | Clears after each submission and after 60 seconds idle | Not applicable |
| Rate limit | 30 entries per minute per device account | See §11.2 |
| Bot check | None needed (signed-in device) | Yes (§11.3) |
| After submit | "Thanks, <first name>. Check your email to finish." Then back to start. | The same words, then a check-your-email page |
| Staff view | "Waiting to finish" list on the kiosk's team page | The registration's entries screen |

### 5.1 One screen at a time

Both modes use a short question per screen, in task order, like Forms' one-question steps where they exist. Copy follows `ui-copy-directions`: plain and short, labelled by the question answered.

1. "Who is joining?" Ways to join, as buttons (the labels are the organization's words).
2. "What's their name?" First and last.
3. "What's their email?" Asked twice on the kiosk, with a typo hint (§7.3).
4. Questions the way to join marks for the first step (grade or graduation year; own page for each).
5. "Who is their guardian?" Only when the way to join needs a guardian for this person (§7.4). Name and email.
6. "Anyone else joining with them?" Repeat steps 2–5 for each. Self-service lets this wait until after verification.
7. Done.

A guardian registering children is a household: the verified person is the guardian; each child is added with step 2 and step 4.

### 5.2 Kiosk access

The kiosk is a signed-in device like the time kiosk. It reuses the time kiosk's gate: admins and direct members of the kiosk accounts team (`time_kiosk_users_team`, `lib/settings.rb:146`) with the additional requirement that they manage the registration's team or an ancestor. Registration-specific override: a setting `intake_kiosk_users_team` (blank means the time kiosk team). The kiosk layout is a copy of `layouts/kiosk.html.erb` with no navigation, no search and no links out. Because the account is a person, its name and photo are hidden on intake screens; the header shows the registration's title only.

An unsigned device that opens the kiosk address is sent to sign in, then back. Closing the browser tab leaves the manager signed in, as with the time kiosk; the spec accepts that (the kiosk shows nothing private and creates nothing the manager couldn't create). Section §11.8 lists what the kiosk account can and can't reach.

## 6. Families, matching and merging

### 6.1 Household registration

A household entry holds one verified adult and any number of people they add. After verification each person gets a `Person`. Guardian relationships are created from the household shape, never typed by staff:

- The verified adult adds children: relationship from the relationship type the way to join names (e.g. a parent type with `guardianship: minor`).
- The child registers on their own and names a guardian: the guardian becomes the household's verified adult when they confirm (§6.2).

The household is the unit of one email sent and one login created per adult. Siblings share a guardian by being on the same household. A second household for the same guardian email is the "returning family" case (§6.3).

### 6.2 A young person registering and naming a guardian

A person who needs a guardian (§7.4) can't finish until one is linked. The entry holds the guardian's name and email. The guardian gets "<Name> would like to join <team>. Confirm you are their guardian." Opening the link verifies the guardian's email, creates or finds their login (§6.3) and creates the guardian relationship. If the guardian never confirms, the application stays "Waiting for a guardian" and the manager sees it. The manager can type a different guardian email, or link an existing person from the application page.

A guardian confirming is a statement, not proof. The manager approving sees "Guardian confirmed by email on <date>" and decides. Intake never lets a minor create a guardian tie that the guardian did not confirm.

### 6.3 Matching, not duplicating

Matching is server side, runs only at verification, and is never shown to the applicant:

1. **Login email.** If `users.email` matches (case-insensitive, trimmed), the verified entry attaches to that person. The person sees "Welcome back" after signing in. No new `User` or `Person` is made.
2. **Name and, where recorded, birthday, among people with no login.** A possible match is held for the manager: the application page shows "Might be the same person as <name>. Link or keep separate." The default is keep separate, so a wrong match never merges two real people.
3. **Guardian by email.** A guardian email matches the way an adult's does (1). A guardian who already exists is linked, not created.
4. **Within the household.** The same name entered twice, or two children with the same email, is rejected on that screen: "You already added <name>."

Nothing here tells a public requester whether someone exists. The screen for step 1 is identical whether or not the email has an account. Only the email the owner receives differs (§11.1).

The kiosk uses the same rules, shown only to the manager as "Waiting to finish" rows with a "Possible match" flag, never on the shared screen.

### 6.4 Merging

Intake prevents duplicates; it doesn't merge them. Merging two people means moving memberships, relationships, badge assignments, tokens, form responses, sign-ups, punches and check-ins and keeping one audit trail. That is its own admin feature, `feature/person-merge`, listed in Phase 6. Until then, managers use the "Link or keep separate" choice above, and the `find_duplicate_people` MCP tool as today.

## 7. Accounts

### 7.1 Email verification

No `Person` or `User` is created from a public request until its email is verified. The verification link is single use, expires in 48 hours, and is stored as a digest (§16.1). On a first visit it creates the records and asks for a password. Where a login already exists, the link only says "Sign in to continue", with a normal sign-in link back to the registration; it never signs anyone in. Intake does not add a login path.

This protects two things: an attacker can't create records for someone else's email, and a typo'd address creates nothing.

### 7.2 Where the email lives

The email belongs on the `User` (`person.rb:24`). Before verification it lives on the entry, encrypted at rest (`encrypts`, see §11.7). On the kiosk, the `User` is created immediately with a random password and the email marked unverified (§16.1: `intake_login_verified_at`); the invitation link verifies and sets the password. Forgot-password also verifies, because it proves control of the mailbox.

### 7.3 Typo defence

On the kiosk the email is typed twice and compared; a mismatch blocks. Both modes show a hint for common domain slips: "Did you mean gmail.com?" The list is a setting (`intake_domain_hints`, one `typo=correct` per line). The person's own screen after verification shows the email and a one-click "Change email" that re-verifies. An invitation that isn't opened within 3 days appears in the manager's "Waiting to finish" list with its age, so a typo is found while the person is still reachable.

### 7.4 Minors and the guardianship age limit

"Needs a guardian" is decided by the existing rules: the person's birthday and `Relationship.guardianship_age_limit` (`relationship.rb:30`), 18 when no limit is set, as Forms does (`form_access.rb:116-120`). With no birthday on file, intake asks for the grad year or birthday (the way to join says which) and treats unknown as needing a guardian, as `signer_roles` does (`form_access.rb:104`).

For a person who needs a guardian:

- The person's own login is created but their email receives nothing from intake until a guardian is linked, except the confirmation that they started. The guardian's confirmation email is sent first.
- A person of age may register without a guardian, but the way to join can still say a guardian signs a form (the existing `guardian_if_minor` signer).
- A guardian for an adult is allowed only through consent relationships (`consented`), created outside intake.

When a person passes the age limit mid-season, nothing in intake changes: guardianship rules go by age when evaluated (`active_guardianships`, `relationship.rb:15`). At the next renewal the guardian's signature requirement falls away by itself, and the person signs for themselves.

### 7.5 Every email gets a login

Matches the HBR norm in a generic way: any person with a verified email has a `User`. People without an email are possible only through the staff path (§1.2). Intake never creates a `User` from a name alone.

## 8. Placement

Approval does what a manager used to do by hand. A way to join has **placement rules**, evaluated in order when an application is approved. Each rule has a condition and outcomes. Several outcomes can fire for one person ("any of" in each list of teams or badges means the same team is joined only once).

| Condition kind | Meaning |
|---|---|
| Always | Every approved person |
| Person field | A person field equals one of the listed values; the mapping can be a table (value to team) |
| Age | Age on the season start in a range |
| New to | The person has never been on any of these teams (or below them) before this season |
| Needs a guardian | By the rule in §7.4 |

| Outcome kind | Meaning |
|---|---|
| Join team | Add a `Membership`. Idempotent. |
| Link guardian to team | The guardian also joins this team (e.g. a family team). Only when a guardian is involved. |
| Grant badge | Assign a badge that records a fact for this season |

- **Class team from grad year.** A "Person field" condition with a value-to-team table.
- **Rookie determination.** "New to" with the listed teams. A grant-badge outcome gives "<season> new member". The badge records the fact that they were new that season. It is not removed later, and it is not used as a status flag by intake itself.
- **Parent team.** "Link guardian to team".

The result of placement shows on the approval screen before the button is pressed: "Will join: <team>, <team>. Will get: <badge>." Placement is the missing-class-team fix: the manager no longer remembers anything. If a needed fact is missing (grad year blank), the Approve button is disabled with "Needs a graduation year" and links to the field. Managers can set the field themselves from the application page, using the person field's own write level.

"Rookie" is not defined in the code. "New to" counts teams the person is on now plus teams recorded by a seasonal fact (the season badges). It can't see someone who left and was deleted; the sample data and Appendix A note the import of last year's roster that closes this gap.

Approval is still `MembershipApplication#approve!`. Placement is a service object, `Intake::Placement.apply(application)`, called from a concern included into `MembershipApplication` that runs after `approve!` saves (`after_commit` on a change to `approved`), in the same transaction as the membership when possible. Upstream's file is not edited.

## 9. The season, the checklist and renewal

### 9.1 Season

Intake needs "this season" in three places: what a registration is for, what "signed this season" means, and when returning members are asked again. Options:

1. A season model.
2. Dates on the registration only.
3. Treat each season's forms as new forms (`Form#duplicate!`, `form.rb:290-296`), and let completion badges carry the season.

Recommendation (Decision 1): a tiny `Season` model (`name`, `starts_on`, `ends_on`, optional `team_id`), in `feature/seasons`, which both intake and requirement sets depend on. It carries no behavior beyond `Season.current(team)` and `contains?(date)`. If the companion spec prefers dates on a requirement set, intake works by reading `registration.season_starts_on` through a method both define; §13 lists that as the one thing to agree.

Why a model rather than option 3: duplicating forms each year splits the history of one person's signatures across forms, bloats the forms list, and still needs someone to remember. Why not dates alone: the same dates must reach forms, checklists, the dashboard card and reports.

**Forms renew each season.** An additive change in `feature/seasons` (not an edit to `feature/forms`):

- A form gains `renews_each_season` (boolean, default false) and `season_team_id` (defaults to the form's team).
- A concern prepended to `FormResponse` overrides `reconfirmation_reason` to return `:season` when the form renews each season and the active submission's `activated_at` (`db/schema.rb:394`) is before `Season.current(team).starts_on`.
- The response then reads "Needs re-confirmation" with the reason "New season". This is the existing state; nothing in the Forms UI is new.
- A scheduled job (`SeasonRolloverJob`, the first run on the season's start date) resyncs the responses of those forms, the way `publish!` does (`form.rb:281`). Until then nothing changes on the day.
- The completion badge follows the existing rule: the badge is removed while the response is not complete (`form_response.rb:124-125`). A form that should keep recording the fact uses no completion badge; the checklist reads the status.

Forms that don't renew keep today's behavior. "Sign it again even if they signed last year" is turning that switch on.

**Confirming information** is a form too: a form of "updates profile" questions (`form_response.rb:51`: these start from the current profile) with a final "These are correct" confirmation. Switched to renew each season, a returning member sees their details already filled in and must press the confirm button and sign. Nothing else is invented.

### 9.2 Renewal

Returning members are already on the team, so renewal is not an application (the policy refuses one: `membership_application_policy.rb:23`). It is the same registration, in "renew" mode:

- Who is returning: members of the registration's teams (or below) at the season's start, or holders of a listed "last season" badge. Both are conditions the way to join states.
- A returning person opens the link, signs in, and lands on their checklist for the season: "Renew for 2028". Their household's other members appear as tabs. A guardian sees each ward's checklist (§9.4).
- When the checklist is Met, intake records the fact "renewed for the season" and nothing else. What that fact is (a badge, a row, a derived state) is Open question 2.
- Returning members who don't finish by the close date show in a managers' list ("Haven't renewed"). Intake never removes anyone. A manager acts on the list with the existing membership screens.
- Wrong information is corrected in the form, which writes to the profile (`update_profile`). Intake has no second place to edit a profile.

Returning members who arrive from a link while signed out are prompted to sign in; "Forgot password" is the same link on the sign-in screen. Intake never says whether the email exists (§11.1).

### 9.3 The joining checklist

The checklist is a requirement set "Join <team> for <season>" (companion spec). Intake needs these checks, all from that spec's registry (§13): a form complete for the season, a form signed by a guardian, profile confirmed this season, has a login, a badge held (FIRST registered, FIRST consent), another set, a commitment met (dues in hours or dollars). Each shows Met / Pending / Not met / Exempt with a "how to fix" link.

Items outside GatherPack:

- **FIRST registration and consent.** Synced by script into season badges (Appendix A). The checklist shows "Registered with FIRST" as a badge-held check. Its fix link goes to an informational page the organization writes (a `Page`), because GatherPack can't file for them. Intake adds no integration.
- **Dues or fees.** A commitment-met or badge-held check, depending on how the books are kept. Intake collects no payments.
- **Background checks and training.** A badge-held check, granted by whoever verifies. Intake doesn't run them; it shows who is waiting.

### 9.4 Who acts on a checklist

A person acts on their own. A guardian acts on a ward's checklist the way sign-ups handle on behalf of: the checklist page offers a household switcher; a guardian signs the forms the form allows them to (`form_access.rb:104`), and sees only what the ward's checklist shows, nothing more of the ward. A guardian who is not the verified adult of the household can act after their own verification.

Guardian wording and counts appear only when a guardian is reached: a young person registering themselves sees "Your guardian will be asked to sign these." A person of age sees nothing about guardians.

## 10. Approval

### 10.1 Who approves

Managers of the target team and its ancestors, and admins, exactly as `MembershipApplicationPolicy#update?` allows (`membership_application_policy.rb:28`). Intake adds no approver role and no setting that stops anyone acting. A sign-up-style delegated organizer for registrations is out of scope; if one is wanted, it reuses `OrganizerGrant` (Open question 4).

No one approves their own application or a relative's. This is the same rule as sign-up decision 14.

### 10.2 What the manager sees

The team's applications page (the existing `index` screen, `membership_applications_controller.rb:5`) gains columns, without changing its URL:

- Name, way to join, source (link, kiosk, own request), submitted, waiting-for (guardian, forms, FIRST).
- Checklist status as counts: "4 of 6 met". Opening a row shows the checklist with each item's status and, for pending items, who owes it ("Waiting for guardian to sign").
- Placement preview ("Will join ...").
- Flags: possible match (§6.3), email never opened, no guardian yet.
- The message from the applicant and reviewer notes.

Applicant details beyond the application are visible only as the manager's existing permissions allow. A manager of the target team can't see the person's profile until approval, unless the existing person scope reaches them (a guardian, a teammate). Intake shows the answers in the form the manager may read, through `FormAccess` (the question's own read level).

### 10.3 Bulk approve and deny

- Select rows, **Approve** or **Deny**. Approve skips any row that doesn't pass the checklist gate or is missing a placement fact, and says why per row ("Skipped 2: needs graduation year").
- Deny asks for a reason, sent to the applicant, stored as `reviewer_notes`. A denied person can be told only what the reason says (§12). A denial is kept; a reapplication is allowed in a later registration.
- Each decision writes a PaperTrail row (§11.6) and fires hooks (§14).

### 10.4 When there is no approval

A way to join marked "no approval" adds the membership when the entry is verified. The checklist still runs. The team's `join_permission` remains as is; intake creates the `Membership` directly through the same service, recorded as source `registration`.

### 10.5 What an applicant can see before approval

Nothing of the team. The applicant's pages are `/join/<slug>/me` (status, checklist, forms they must complete, a way to withdraw) and the forms themselves, each limited by the form's own access. `PersonPolicy::Scope` already shows a person with no teams only themselves (`person_policy.rb:5-8`), so no roster, event or people screen reveals anything. One exception: `TeamPolicy::Scope` lists `requires_approval` teams to every signed-in user (`team_policy.rb:7-9`), and the team's public page (`teams/show_public.html.erb`) shows its managers. This is upstream behavior for teams that accept applications. The decision: intake does not change it; the team's description and managers' names are already public by that choice. Teams that should be hidden use "no approval" with a link-only registration (Open question 5).

### 10.6 Capacity and waiting list

A way to join can carry a cap. Past it, entries become `waitlisted` (an additional application status, `status: 3`, added with a fork migration that adds no column) and managers promote them by hand. It is listed as later work (Phase 6) because the status enum belongs to upstream (§18).

## 11. Security

This is the riskiest public surface in the app: it collects minors' data from people nobody has verified. The 2026-10 audit found many issues in features far smaller than this (notes/audit). The controls below are part of Phase 1; none is a later hardening.

### 11.1 No account enumeration

- Every public response is identical for any email: same page, same status, same words, same timing target. The only difference is the email delivered.
- Existing account: the email says "You already have an account. Sign in to continue." with a sign-in link and the registration link. No password reset is triggered by intake.
- Matching, duplicates and guardian existence appear only in staff screens (§6.3).
- The email field's error messages are format only. There is no "is taken" error on the public form.
- Timing: the controller always enqueues the same job and renders the same view; matching happens in the job. The page never queries `users` by the submitted email.

### 11.2 Rate limits

Rails `rate_limit` with `Rails.cache` (Solid Cache in production), as the kiosk and MCP controllers do. Defaults, all settings:

- Starting an entry: 5 per hour per IP, 3 per hour per email address (digest, not plain), 200 per hour per registration.
- Verification link: 10 attempts per hour per IP.
- Resend: 3 per entry per day.
- Kiosk: 30 per minute per device account.
- Staff screens use the app's normal protections.

Over the limit, the response is the same page with "Try again in a few minutes." It does not name which limit.

### 11.3 Bot protection

- A honeypot field and a minimum time on the form (a signed timestamp in the form; submissions faster than 3 seconds are quietly dropped).
- An optional challenge behind a seam, `Intake::BotCheck`, with a Cloudflare Turnstile implementation off by default (settings: site key, secret key). HBR already fronts the app with Cloudflare, so Turnstile is the first adapter. Self-service on with the challenge off is allowed but shown in the registration's setup page as "No bot check".
- A global cap on unverified entries per registration (default 500). At the cap, new entries show "Registration is busy. Try again later." and managers are notified once.

### 11.4 Verify before records

No `Person`, `User`, `Relationship`, `MembershipApplication` or form response exists for self-service until the email is verified (§7.1). An entry holds the minimum before verification: first name, last name, email, way to join. Nothing about children, birthdays, medical data or phone numbers is collected until the person is verified. This keeps a flood of fake entries from becoming real people, and keeps anything sensitive off unverified rows.

### 11.5 Abuse cleanup

- Unverified entries expire after 7 days and are deleted by a recurring job (a line in `config/recurring.yml`).
- A manager's entries screen shows counts by day and source IP prefix (a truncated /24 or /48, kept 30 days, never shown outside the screen), with **Delete selected** and **Close registration** (stops new entries instantly).
- A verified application the manager denies as spam can be **deleted with its person and login** when the person has nothing else (no memberships, responses or relationships). The screen states what will be deleted. Admins only; the action is audited.
- The registration page can be closed by an admin from the MCP tool set as well as the app (§15).

### 11.6 Audit trail

- Every intake model has `has_paper_trail versions: { class_name: "AuditLog" }`.
- Public requests have no signed-in user, so `user_for_paper_trail` returns nil. A public-request concern sets the whodunnit to the entry's neat id (`entry:<id>`) so each created record points to the entry that made it. For kiosk requests it is the device account.
- Decisions record the actor, the checklist state and the placement actually applied, in the application's own audit row, so a later question "why was this person approved?" has an answer.

### 11.7 Data protection

- Entries encrypt the email and any minor's facts (`encrypts`). Active Record encryption isn't configured today (`grep encrypts` finds none), so Phase 1 adds the keys to credentials. This is the one new secret.
- Tokens are random, 128-bit, stored as SHA-256 digests, single use, short-lived.
- No emails carry personal data other than first names and the team's name. Links are one-time.
- Nothing from an entry appears in URLs, logs or the flash. Rails parameter filtering covers `email`, `guardian_email`, `token` and answer fields.
- Forms and person fields keep their read and write levels; intake adds none.

### 11.8 The kiosk account

The kiosk account can open `/join/<slug>/kiosk` and nothing more by that route. It can do what the person who signed in can do elsewhere (it is their account). The spec adds no extra power and takes none away. The kiosk screens render no data from existing records, so a bystander sees only what the person typed.

### 11.9 Other

- The slug is unguessable by default (a random string); a friendly slug is allowed but not enumerable because closed registrations answer the same page as unknown ones.
- Open redirects: sign-in return paths are internal only.
- CSRF is on; the entry form is a normal Rails form, no JSON API for the public.
- A registration's HTML sets `noindex`.
- Brakeman is run on the branch and clean, like the rest of the fork.

## 12. Notifications

Sent with `SendEmailJob` (`app/jobs/send_email_job.rb`) through the email gateway. Texts are short and plain; each is a setting-less default that an organization can override in the registration's setup.

| To | When | Says |
|---|---|---|
| Person | Entry created | "Finish joining <team>. This link works for 48 hours." |
| Person with an account | Entry created | "You already have an account. Sign in to continue." |
| Guardian | Entry names them | "<First name> would like to join <team>. Confirm you are their guardian." |
| Person and guardian | A checklist item is waiting on them, 3 and 10 days after (like `FormScheduleJob` reminders) | "Still to do: <item>" with the fix link; a guardian's text only when the guardian owes it |
| Managers | New application; digest daily, not per application | "<n> new people are waiting to join <team>." |
| Managers | Entry cap reached | "Registration is busy." Once. |
| Person | Approved | "You're in. <team>. Next: <anything still unmet>." |
| Person | Denied | The reason the manager typed, or "We can't take your application right now." if blank |
| Returning member | Season opens, 14 days before the close, and the day before | "Renew for <season>." |

Opt-outs follow whatever the gateway offers; intake adds none. Nothing is sent to a minor's address until a guardian is linked (§7.4).

## 13. What this needs from requirement sets

For the two specs to meet. Everything here is a request to the requirements spec; intake designs none of it.

1. **A set can be attached to a registration's way to join**, and a person's status in it can be asked for: `RequirementSet#status_for(person)` returning the overall state and a list of items (name, state, how-to-fix path or nil, owed-by: the person or their guardian).
2. **Populations the sets can use:**
   - "Pending applicants to team X" (people with a pending `MembershipApplication`, for a given registration).
   - "Members of team X at season start" (returning members; needs the season start date).
   - "Applicants and members" combined, for the joining checklist, so one set can show both.
3. **Check kinds intake relies on:**
   - *Form complete for the season*: the form's response is complete and the active submission was activated on or after the season's `starts_on` (`form_submissions.activated_at`, `db/schema.rb:394`). Works for forms that don't set `renews_each_season`; for ones that do, it is the same as the form's own status.
   - *Profile confirmed this season*: the same check, bound to the "confirm your information" form.
   - *Guardian signature complete*: a form whose signer is a guardian (`signer: guardian` or `guardian_if_minor` and the person is under the age limit) has the signature. If no guardian is linked yet: Pending, "needs a guardian".
   - *Badge held* (FIRST registered, FIRST consent, background check).
   - *Has a login*.
   - *Commitment met* (dues in units).
   - *Another set*.
4. **Guardian acting on a ward's items**: each item reports whether the viewer may act on it for the subject (a guardian for a ward), using `FormAccess.signer_roles` for forms. The how-to-fix link is for the subject's context, not the viewer's.
5. **Exempt as a state with a reason**, to let a manager waive an item for one person. Intake shows who waived it and when.
6. **A form's audience may be a population.** Gap 2 of §2.3: an applicant is in no team, so a form scoped to the team never appears for them. Intake needs a form audience rule target `population` pointing at "pending applicants to team X" (a new `target_type` beside `team`, `badge`, `person`, `form_audience_rule.rb:15`, added by a concern in the requirements branch). Until that exists, an interim in intake's own branch adds a `pending applicants of team` rule type. Reconciled: requirements §10.3 provides it as the form audience choice "People this list covers" (`Requirements.people_covered_by(set)`).
7. **A native report page** for "everyone with an open joining checklist" with the same states. Intake links to it from the registration page and shows nothing else.
8. **Season is an input**: sets read `Season.current(team)` or the set's own dates (§9.1). Reconciled: requirements §12 and Decision 10 adopt `feature/seasons`; a set with a season takes its window from it.
9. **A change event.** When any item's state changes, the set fires an event so intake can notify and so the dashboard card can refresh. Intake does not poll. Reconciled: the requirements spec fires `requirement_results - status changed` (hook) and `requirement_status_changed.gatherpack` (notification) from its refresh job, per item and for the overall row (requirements §8.3). Intake listens to the notification.
10. **Cost.** Statuses for a team's applicants must be computable in one query path per check kind (batch API), not a per-person loop; the approval page shows about 200 rows.

## 14. Hook events

Registered through `GatherPack::HookCatalog` like `config/initializers/hook_events.rb`:

- Model targets (`register_targets`): `intake_registrations`, `intake_ways_to_join`, `intake_entries`, `intake_placement_rules`, `seasons`.
- Events (`register_events`):
  - `intake_entries - verified`
  - `intake_entries - expired`
  - `membership_applications - submitted`
  - `membership_applications - approved`
  - `membership_applications - denied`
  - `intake_registrations - opened`
  - `intake_registrations - closed`
  - `intake_renewals - completed`

`membership_applications` model events already fire for create, update and destroy through `CanBeHooked`; the new events carry the explicit meaning. Hooks run with `eval` and `model` in scope (gp-map), so the same caution applies: only admins write them.

## 15. MCP (`feature/mcp-intake`)

Tools allow exactly what the app allows; none is MCP-only. Existing tools already cover approval (`decide_membership_application`, `list_membership_applications`, `withdraw_membership_application`).

| Tool | Scope | App equivalent |
|---|---|---|
| `list_registrations` | read | The registrations screen |
| `get_registration` | read | Setup page, link, counts, state |
| `set_registration_state` | write | Open and Close buttons |
| `list_intake_entries` | read | Entries screen, without emails (the app shows them only to the team's managers; MCP follows that) |
| `delete_intake_entries` | write | Delete selected |
| `get_application_checklist` | read | The checklist row on the applications page |
| `decide_membership_application` | write | Extended to accept a deny reason and to report skipped bulk rows |
| `list_waiting_to_finish` | read | The kiosk team page list |
| `list_returning_members` | read | "Haven't renewed" |

Not exposed: creating public entries (the public flow has no API), minting links, changing bot-check secrets, deleting people with their logins (admin screen only; tool mirrors it only for admins if it is ever added).

## 16. Data

All fork migrations are new and reversible, run for primary. `db/schema.rb` is regenerated.

### 16.1 Tables

| Table | Columns (all new) |
|---|---|
| `seasons` | `name`, `starts_on`, `ends_on`, `team_id` (nullable) |
| `intake_registrations` | `team_id`, `season_id`, `title`, `slug` (unique), `description`, `opens_at`, `closes_at`, `state` (draft, open, closed), `self_service` and `kiosk` booleans, `successor_id`, `created_by_id` |
| `intake_ways_to_join` | `registration_id`, `name`, `position`, `needs_approval`, `guardian_rule` (never, by age, always), `relationship_type_id`, `form_id` (questions step), `requirement_set_id`, `cap`, `returning_teams` (ids) |
| `intake_way_teams` | `way_id`, `team_id` (the target teams, "any of": each ticked team makes one application) |
| `intake_placement_rules` | `way_id`, `position`, `condition_kind`, `condition_data` (jsonb), `outcome_kind`, `outcome_data` (jsonb) |
| `intake_entries` | `registration_id`, `way_id`, `source` (self_service, kiosk), `email` (encrypted), `first_name`, `last_name`, `facts` (encrypted jsonb), `token_digest`, `expires_at`, `verified_at`, `person_id` (set at verification), `created_ip_prefix` |
| `intake_household_members` | `entry_id`, `person_id` (after verification), `role`, `facts` (encrypted jsonb), `guardian_confirmed_at` |

Additions to existing tables:

| Table | Added column | Why |
|---|---|---|
| `membership_applications` | `registration_id` (nullable, indexed), `way_id` (nullable), `source` (string) | §2.3 gap 4 |
| `forms` | `renews_each_season` (boolean, default false) | §9.1 |
| `users` | `intake_login_verified_at` (datetime, nullable) | §7.2 |

No existing column is modified. `schema.rb` is regenerated, never hand-merged.

### 16.2 Routes

New routes are added by a block at the end of `config/routes.rb` (there is no routes seam yet, gp-map): `/join/:slug`, `/join/:slug/kiosk`, `/join/:slug/me`, `/join/verify/:token`, the staff screens under `/registrations`, `/teams/:team_id/registrations`. A closed registration answers with the same page as an unknown slug unless its successor is set.

## 17. Settings, flag, branches, tests

### 17.1 Flag and settings

`GatherPack::Features.register` with key `intake`, `default_enabled: false`, nav under People: Registrations. Gate controllers with the `before_action` pattern from `forms_controller.rb`. `Settings.register` (group "Intake"):

| Key | Default | Purpose |
|---|---|---|
| `intake_kiosk_users_team` | blank (time kiosk team) | Who can open the intake kiosk |
| `intake_domain_hints` | `gmial.com=gmail.com` and common slips | Typo hints |
| `intake_entry_cap` | 500 | Unverified entries per registration |
| `intake_rate_ip_per_hour` | 5 | Starts per IP |
| `intake_turnstile_site_key`, `intake_turnstile_secret` | blank | Bot challenge |
| `intake_idle_seconds` | 60 | Kiosk reset |
| `intake_entry_days` | 7 | Unverified entry retention |

Settings values are cached per process (gp-map), so a change made by a script needs a restart.

Nothing in intake changes what an existing team or application does while the flag is off. The renewal change to forms (`renews_each_season`) has no effect until a form turns it on.

### 17.2 Branches

| Branch | Content | Depends on | Upstream? |
|---|---|---|---|
| `feature/seasons` | `Season`, `Form#renews_each_season`, rollover job | `feature/forms` | Yes (generic) |
| `feature/intake` | Registrations, ways to join, entries, household, kiosk and self-service flows, placement, application columns, notices | `feature/seasons`, `feature/search-and-add` | Yes (generic) |
| `feature/intake-checklist` | Checklist panel, uses requirement sets | `feature/intake`, requirements branch | Yes |
| `feature/mcp-intake` | §15 | `feature/mcp`, `feature/intake` | No |
| `feature/intake-turnstile` | Turnstile adapter | `feature/intake` | Yes (optional) |
| `feature/person-merge` | §6.4 | none | Yes, later |

Manifest order changes need the owner's approval (AGENT.md rule 8). Each branch is written to upstream's standards and mentions no organization.

### 17.3 Upstream files touched

Kept to the minimum. Everything else is new files, initializers and concerns.

| File | Change | Why |
|---|---|---|
| `config/routes.rb` | One block of routes | No routes seam |
| `config/recurring.yml` | Two lines (expiry, rollover) | No jobs seam |
| `app/views/welcome/dashboard.html.erb` | One render line for the "Renew" and "Finish joining" card | No dashboard seam, only if the card ships |
| `app/models/membership_application.rb` | None. A concern is included from an initializer. | Rule 6 |
| `app/views/membership_applications/` (index) | Columns via a view partial seam if one exists; otherwise a view override listed in `view-overrides.lock` | Checklist column |
| `db/schema.rb` | Regenerated | Rule 9 |

`FORK.md` "Upstream files touched" lists the above.

### 17.4 Sample data

`fork/sample_data/features/intake.rb`, using Northwind names:

- A registration for a coming season with two ways to join (one needing a guardian), placement rules for a class team and a first-time badge, open.
- Entries: one unverified (kiosk), one expired, one self-service verified.
- Applications: one waiting for a guardian, one with the checklist all met, one with a possible match, one denied with a reason.
- A returning family where a sibling joined last season.
- A form that renews each season, signed last season and now Pending.
- A person who turns 18 mid-season.

### 17.5 Tests

- Model: placement rules (grad year table, new-to, guardian-only outcome, idempotent, missing fact); renewal reason `:season`; entry token single use and expiry; matching rules, including no match across households.
- Security: identical responses and query counts for an existing and a new email; rate limits per IP, email digest and registration; honeypot and fast-submission drops; entry cap; unverified entry creates no person or user; expired entries purged; params filtered in logs; kiosk gate for a non-manager.
- Policy: an applicant sees only themselves; a manager of another team can't decide; a guardian acts on a ward but not on an unrelated person; bulk approve skips unmet rows.
- Flow: system test of the kiosk flow end to end (a manager signed in, one child, one guardian) and of the self-service flow with the email link.
- Tooling: `ruby test/fork/sample_data_test.rb`, RuboCop, Brakeman.

### 17.6 Phases

1. **Core (self-service)**: registrations, ways to join, entry, verification, matching, application creation with source, placement, notices, security controls. Flag off. No checklist (a manager sees forms status through the existing Forms report).
2. **Seasons and renewal**: `feature/seasons`, renewal path, rollover job.
3. **Checklist**: on the requirements branch's delivery; gating and the applications page columns; bulk approve.
4. **Kiosk**: kiosk mode, waiting-to-finish list.
5. **MCP and dashboard card.**
6. **Later**: waiting list, person merge, delegated organizers.

## 18. Decisions

Defaults, 2026-11-05.

1. **A small `Season` model** in its own branch, used by intake, forms and requirement sets. Replaces per-season duplicate forms.
2. **Extend `MembershipApplication`, don't replace it.** Added columns, a concern, a service for placement. The model, policy and routes are unchanged.
3. **Verify before records** for self-service. Kiosk creates records at once, marked unverified, because a manager is present.
4. **One flow, two skins.** Kiosk and self-service differ in who can reach them and what they ask, not in logic.
5. **No signatures, medical data or birthdays on a shared screen.**
6. **Identical responses for every email.** Matching only in the job and on staff screens.
7. **Matching never merges.** Login email attaches; name matches are held for a person; the default is "keep separate".
8. **Renewal isn't an application.** Returning members have the checklist only.
9. **Forms renew each season through a switch on the form.** `renews_each_season` plus a rollover job.
10. **"Confirm your info" is a form** of profile-updating questions. No second place to edit a profile.
11. **Placement is configuration on the way to join.** Class team, parent team and the first-time badge are rules.
12. **Approval doesn't wait for the checklist by default.** A way to join can require Met first.
13. **The checklist is a requirement set.** Intake consumes it (§13).
14. **No removal at season end.** Intake lists who hasn't renewed; managers act.
15. **Applicants see only themselves.** Upstream's visibility of approval-gated teams stays as is.
16. **Nothing to a minor's address** until a guardian is linked.
17. **The flag is off by default**, with `renews_each_season` inert until a form opts in.
18. **Entries expire after 7 days.**

## 19. Open questions

1. **Where does the "renewed for the season" fact live?** A season badge (records a fact, one more badge each year), a derived state from the checklist (no stored fact, nothing to report on after the set changes), or a row on a `season_memberships` table. Default: a badge granted when the checklist is Met, named "<season> member"; it's a fact the Eligibility Report can already read.
2. **Which email gets the first message for a minor who has their own address and a guardian address?** Default: the guardian's, first; the minor's after the guardian confirms.
3. **Is a shared access code needed on the public link** (printed at the callout) or is a random slug enough? Default: slug only, code optional.
4. **Who runs registration if not a team manager** (a volunteer coordinator)? Default: managers and admins only; delegated organizers later.
5. **Should a registration's team stay out of the signed-in team list** while it accepts applications? Today every signed-in person sees approval-gated teams. Default: leave as is.

## Appendix A: HBR setup

Configuration only. None of this is in the generic branches.

- **Season.** "2027 season", May 1 2027 to April 30 2028.
- **Registration.** "Join Team 1747 for 2027", self-service and kiosk on, owned by the main team.
- **Ways to join.**
  - *Student*: target "Team 1747 - Students" (approval required); guardian rule by age; relationship type Parent; questions form with grade and graduation year; placement: person field "Graduation year" to "Team 1747 - Class of <year>" (the 2027-2030 teams), new-to "Team 1747 - Students" and the class teams grants "2027 Season Rookie"; guardian also joins "Parents".
  - *Mentor or volunteer*: target the adults team; no guardian; checklist adds the training and background-check badges.
  - *Parent or guardian only*: target "Parents"; no guardian.
- **Checklist for students.** Participation agreement and medical release (signed by a guardian, renew each season); "confirm your information" form; "Registered with FIRST" and "FIRST consent" badges (synced by script from FIRST's roster); dues if that is how the books record it.
- **Forms.** The existing forms in production switch `renews_each_season` on in the release that ships seasons.
- **Kiosk accounts.** The existing kiosk accounts team; callouts use the registration kiosk address on a laptop in the room.
- **Before the first season.** Import last season's roster so "new to" sees returning students; match students and guardians by email first. The old import scripts stay in `~/dev/gatherpack-import` and are not re-run.
- **Google Form.** Stays until the first intake season is verified; the link on the website changes to the registration link.
- **Hook examples.** Welcome email on approval; a notice to the events coordinator when a mentor is approved.
