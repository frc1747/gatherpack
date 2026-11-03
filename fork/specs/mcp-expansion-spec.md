# MCP server expansion spec

Extends [`mcp-spec.md`](mcp-spec.md). That spec built the server, sign-in, registry, call log and a first set of tools. With those tools, an AI client can answer most questions about GatherPack's data but can make few of the changes an organization usually makes. This spec adds the missing writes and reads: the person record and its fields, logins, relationships, the time clock (including clocking everyone out at the end of a meeting), scan tokens, sign-up roster actions, commitment adjustments, form answers, and reads for the remaining features. It also lists what stays out of MCP, and why.

Everything in `mcp-spec.md` still applies (§1 principles, §5 transport, §6 tool classes, §8 call log, §12 tests) unless a section below changes it.

## 1. Goal and measure

The test is the routine work an admin or team manager does on the site today:

| Routine work | Today | After this spec |
|---|---|---|
| Compare sign-up sheets kept elsewhere with sign-ups and check-ins, then fix the differences | Read only, except `place_signup`, `remove_signup` and `record_checkin` | Also move, mark and edit sign-ups, and remove check-ins (§5.6, §5.3) |
| Add a new member or parent, with a login | Not possible | `create_person`, `add_login`, `add_relationship` (§5.1, §5.2) |
| Update a profile field for one or many people (an eligibility flag, a shirt size) | Read only | `update_person`, `update_person_fields` (§5.1, §5.5) |
| Badge sync from an outside roster | `assign_badge` and `remove_badge` | Unchanged; the connected account needs permission for the badge |
| Clock everyone out at the end of a meeting; fix a punch | Read only (`clocked_in_now`) | `clock_out`, `record_punch`, `update_punch`, `remove_punch` (§5.4) |
| Give someone a scan card | Not possible | `list_tokens`, `add_token`, `remove_token` (§5.4) |
| Credit or correct commitment progress by hand | Read only | `add_commitment_adjustment`, `remove_commitment_adjustment` (§5.7) |
| Enter a form answer someone gave on paper | Read only | `save_form_answers` (§5.8) |
| Schedule or fix a meeting | `create_event` only | `update_event`, `remove_event` (§5.3) |
| Read reports kept as Pages | Not possible | `list_pages`, `get_page` (§5.9) |

Work that edits code or configuration, imports files, or reaches the database or servers stays out of MCP (§3).

## 2. Changes to the principles

`mcp-spec.md` §1 stands, with these changes:

1. **A write shows and changes nothing a page wouldn't.** Each write names the page action it mirrors and applies that action's policy call, its permitted attributes, and whatever the controller filters. Where a page silently drops a change it doesn't allow (`PeopleController#person_params` and `limit_to_manageable`, `Person#assign_field_values` for unwritable fields), the tool refuses that part and names it. It never reports success for a change it didn't make.
2. **Bulk writes only where a page has the same bulk action.** Principle 4 ("one change per write call") gets one exception. A tool may change several records when an existing page or the kiosk does the same thing in one action: clocking out a period or all periods (kiosk Time Management), Mark all brought (sign-up roster). Such a tool:
   - takes a `dry_run` boolean (default `false`) that returns exactly what would change without changing it;
   - changes at most 200 records per call and refuses beyond that;
   - checks permission on each record, with the same rule as the single-record tool, and skips records it may not change. It returns `{ changed: [...], skipped: [{ id, reason }] }`;
   - writes one call log row, with every changed record (§6).

   Anything else that looks like a bulk job (a column of profile values, a roster of badges) is a series of single-record calls made by the client. That keeps each change visible in the client's tool approvals and in the log.
3. **Moves are one call where the page has a Move.** `move_signup` mirrors the roster's Move, so notices, capacity checks and hooks run once, as on the page. It is not a remove followed by a place.
4. **Minors' contact details stay out, both ways.** The owner's decision in `mcp-spec.md` (built-in email, phone, address and birthday, plus phone- or email-type custom fields, are withheld for anyone under 18 or with no birthday) also covers writes. A tool refuses to set a withheld field for a withheld person, because the client can't read the result back. Login email is the exception (§5.2): it is how a login is made, and it is returned only as `has_login: true`.
5. **Writes return what the read tool shows.** After a change, return the record in the same shape as its read tool (`get_person`, `get_event`, `list_punches`), so the client can confirm the change without another call.
6. **Never rely on a default.** On public builds `ApplicationPolicy` allows any action a policy doesn't define. The private security series makes it deny. A tool relies only on policy methods its policy defines (all the ones named below exist as of hbr.27). It gates everything else on the parent record, as `mcp-spec.md` §1.2 says.

## 3. Out of scope, and why

| Area | Reason |
|---|---|
| Hooks, Reports, Variables, dynamic Page source, Widget ERB and JavaScript | Stored code that runs in the app process. Changing it through an AI client would put code execution behind a chat. Rendered Page output is in scope, read only (§5.9). |
| Settings, Gateways, OAuth applications, Themes, feature flags | Site configuration and secrets. One mistaken call would change the whole site. |
| Audit Log and MCP Calls | Admin-only logs of everyone's activity. They stay as locked down as they are; no tool reads them. |
| Users' admin and architect flags, impersonation, deleting a person or a login | Escalation and irreversible removal. These stay on the pages. |
| Ledger, budget, payment and transfer writes | Money. The ledger read tools stay (`list_ledgers`, `ledger_entries`). |
| Mailboxes and mailbox messages | Other people's email, and attachments. |
| Sending email outside an existing flow | Tools never send mail of their own. Mail that a mirrored page action already sends (sign-up notices, confirmation of a moved sign-up) is still sent, as on the page. |
| Building forms, sign-up sheets, positions, slots and commitments | Many-field builders with previews. A client should hand an organizer a link instead. Reconsider after the trial (§11). |
| Imports from files (PDF rosters, CSV exports) | The client reads the file and makes single calls. No upload tool. |

## 4. Branches

New tools go on the branches that already hold their area (`mcp-spec.md` §2). No new branches:

| Branch | Adds |
|---|---|
| `feature/mcp` | §5.1 to §5.4, §5.9, §5.10; the bulk-write support and call log change (§6) |
| `feature/mcp-person-fields` | §5.5 |
| `feature/mcp-signups` | §5.6 |
| `feature/mcp-commitments` | §5.7 |
| `feature/mcp-forms` | §5.8 |

Connector branches keep touching no upstream files. The new migration (§6) is on `feature/mcp`.

## 5. Tools

Each table gives the tool, its inputs, its effect or result, and the page action whose checks it mirrors. Before writing a tool, confirm that action against its controller, then copy the rule actually used into the class comment, as `mcp-spec.md` §7 asks. All write tools have scope `mcp_write` and need `mcp_write_enabled`.

### 5.1 People (`feature/mcp`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `create_person` | `first_name`, `last_name`, `display_name?`, `email?`, `team_id?`, `manager?` | Creates the person. With `email`, also creates the login as the page does (§5.2), but never returns or logs the generated password: the person uses Forgot password. With `team_id`, adds the membership in the same transaction. Returns `get_person` | `PeopleController#create` with `PersonPolicy#create?`; the membership through `add_team_member`'s rule, all or nothing |
| `update_person` | `person_id`, any of `first_name`, `last_name`, `display_name`, `bio`, `email` | Changes the given attributes only | `PeopleController#update`: `PersonPolicy#update?`, then `update_profile?` for these attributes (the page drops them without it). `email` follows §2.4 |
| `find_duplicate_people` | `first_name`, `last_name`, `email?` | People in the viewer's scope with the same name, the same name after trimming and case folding, or the same login email (as `has_login` only) | `policy_scope(Person)`. Clients call it before `create_person`; `create_person` doesn't refuse duplicates, because the page doesn't |

Built-in profile details other than these (phone, birthday, address) are person field values and go through `update_person_fields` (§5.5) when person fields is on. Without person fields, `update_person` doesn't offer them, just as the page doesn't.

### 5.2 Logins and relationships (`feature/mcp`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `add_login` | `person_id`, `email` | Creates the login for a person who has none, with a random password nobody sees. The person uses Forgot password. Returns `{ person, has_login: true }` | `UsersController#create` with `UserPolicy#create?` on the person's `User.new`. Refuses if the person already has a login or the email is in use |
| `list_relationship_types` | — | Relationship types with parent and child labels and whether they grant guardianship | `policy_scope(RelationshipType)` |
| `add_relationship` | `parent_id`, `child_id`, `relationship_type_id` | Creates the relationship; returns it with both people | `RelationshipsController#create` with `RelationshipPolicy#create?`, and both people found the way the controller finds them (`policy_scope(Person)` or `related_people`) |
| `remove_relationship` | `relationship_id` | Removes it | `RelationshipsController#destroy` with `RelationshipPolicy#destroy?` |

`get_person` already lists guardians and wards. Add each relationship's `relationship_id`, only for viewers who may remove it (the pattern used for `membership_id`).

### 5.3 Teams, events and check-ins (`feature/mcp`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `update_team_member` | `membership_id`, `manager` | Sets or clears the manager flag | `MembershipsController#update` with `MembershipPolicy#update?` |
| `list_membership_applications` | `team_id?` | Pending applications the viewer can act on | `policy_scope(MembershipApplication)` and `index?`, as the page |
| `decide_membership_application` | `membership_application_id`, `decision` (`approved`/`denied`) | Approves (creating the membership) or denies, as the team's applications page does | `MembershipApplicationsController#update` (`approve!` / `deny!`) with `MembershipApplicationPolicy#update?`. Withdrawing (`#destroy`) is the applicant's own act and isn't offered |
| `update_event` | `event_id`, any of `name`, `description`, `starts_at`, `ends_at`, `location`, `event_type_id`, `locked`, `time_clock_period_id` | Changes the given attributes. Time changes reschedule sign-up reminders and notify sign-ups, as an edit on the page does | `EventsController#update` with `EventPolicy#update?`; `team_id` isn't changeable here |
| `remove_event` | `event_id` | Removes an event with no check-ins and no sign-ups | `EventsController#destroy` with `EventPolicy#destroy?`. Refuses when check-ins exist (deleting one fails today, BL-005) or when sign-ups exist, naming the count |
| `remove_checkin` | `checkin_id` | Removes the check-in (the page's Checkout). Sign-ups it fulfilled stay fulfilled, as on the page | `CheckinsController#destroy` with `CheckinPolicy#destroy?` |
| `update_checkin` | `checkin_id`, `notes?`, `field_responses?` (`{ checkin_field_id: response }`) | Changes notes and check-in field answers | `CheckinsController#update` and `#field_update` with `CheckinPolicy#update?` and `CheckinFieldResponsePolicy#update?`; notes only if `show_notes?` |

`list_checkins` and `get_event` gain `checkin_id` on each check-in, only for viewers who may remove it.

### 5.4 Time clock and tokens (`feature/mcp`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `list_time_clock_periods` | `active?` (default true) | Periods with team, dates, permission level, open punch count | `policy_scope(TimeClockPeriod)` |
| `list_punches` | `person_id?`, `period_id?`, `from`, `to`, `flagged?` | Punches with person, period, start, end, hours, note, flag. Window ≤ 366 days | `policy_scope(TimeClockPunch)` (punches index); `flagged: true` needs `TimeClockPunchPolicy#flagged?` |
| `record_punch` | `person_id`, `period_id?`, `starts_at`, `ends_at?`, `note?` | Creates a punch; open if `ends_at` is missing | `TimeClockPunchesController#create` with `TimeClockPunchPolicy#create?` |
| `update_punch` | `punch_id`, any of `starts_at`, `ends_at`, `period_id`, `note` | Changes it. Moving it to another person isn't offered | `TimeClockPunchesController#update` with `update?` |
| `remove_punch` | `punch_id` | Removes it | `TimeClockPunchesController#destroy` with `destroy?` |
| `clock_out` (bulk) | One of `person_id`, `period_id`, `all: true`; `dry_run?` | Closes open punches now, each capped at its period's end of day, as the kiosk does. `all` covers every period on the teams the viewer manages (admins: every period). Returns changed and skipped punches | The kiosk's `punch_out`, `punch_out_period` and `punch_out_all`, with the per-punch rule in §5.4.1 |
| `list_tokens` | `person_id` | The person's tokens, values masked to the last four characters | `policy_scope(person.tokens)`, as the profile page lists them |
| `add_token` | `person_id`, `value` | Adds a token to the person. Refuses a value already in use, without saying whose it is | `TokensController#create` with `TokenPolicy#create?`; the value runs through `Token`'s own normalization (`rfidify`) |
| `remove_token` | `token_id` | Removes it | `TokensController#destroy` with `TokenPolicy#destroy?` |

#### 5.4.1 Who may clock out whom

The kiosk's two buttons disagree today (BL-027). Per period, Clock Out needs `TimeClockPeriodPolicy#edit?`, which the private series denies on *added by admin* periods. All Periods closes every open punch on the teams the scanned manager manages. `clock_out` follows one rule for all three forms:

- Admins: any open punch.
- Managers: open punches in periods whose team they manage, including *added by admin* periods. That matches the kiosk's All Periods and the mass clock-out managers already use, and closing a punch can't credit anyone extra time. Their own open punch too.
- Anyone else: their own open punch only.

`update_punch` keeps `TimeClockPunchPolicy#update?`, so editing times stays as strict as the page. Fixing BL-027 should bring the kiosk's per-period button onto this same rule, in the series that introduced it.

Closed punches keep `created_by` as it was; whodunnit and the call log record who closed them. This differs from the kiosk, which overwrites `created_by` with `"kiosk"`.

#### 5.4.2 Token values

A token value is what a card or tag carries. Whoever knows it can clock in as that person at the kiosk. So `list_tokens` masks values, and `add_token` takes a value the client supplies (a scanned card, or one it generates in the organization's format) but never echoes it back in full. The call log stores `add_token`'s value masked too. That is the one exception to §8's "arguments as given".

### 5.5 Person fields (`feature/mcp-person-fields`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `list_person_fields` | — | Field definitions: key, label, group, type, options for selects, required, and whether this viewer can write it for anyone | `policy_scope(PersonField).active` (archived fields left out) |
| `update_person_fields` | `person_id`, `values` (`{ field_key: value }`) | Sets the given fields only. Blank clears one. Returns the person's fields as `get_person_fields` shows them | `PeopleController#update`'s `assign_field_values(..., acting:)` with `only_given: true`. Fields not in `PersonPolicy#writable_person_fields` are refused by name, as are withheld fields (§2.4). Values validated as the form validates them (select options, number, date). All or nothing |

### 5.6 Sign-ups (`feature/mcp-signups`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `move_signup` | `signup_id`, `slot_id`, `override_rules?` | Moves a sign-up to another slot on the same sheet, with the roster's notices | `RosterSignupsController#move` with `SignupPolicy#move?` and `move_to?`; `override_rules` only with `override?` |
| `update_signup` | `signup_id`, any of `quantity`, `answer`, `note`, `on_behalf_of_id` | Changes details | `SignupsController#update` (member) or `RosterSignupsController#update` (organizer), whichever `SignupPolicy#update?` allows |
| `mark_signup` | `signup_id`, `status` (as the roster's Mark offers) | Marks fulfilled, no-show, brought, or back to active | `RosterSignupsController#mark` with `SignupPolicy#mark?` |
| `mark_all_brought` (bulk) | `sheet_id`, `event_id`, `dry_run?` | As the roster's Mark all brought | `RosterSignupsController#mark_all_brought` with `SignupSheetPolicy#roster?` |

`place_signup` keeps returning `signed_up_by` (trial fix). All four return the sign-up as `get_signup_sheet` shows it.

### 5.7 Commitments (`feature/mcp-commitments`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `add_commitment_adjustment` | `commitment_id`, `person_id` (or the group's owing person, as the page resolves it), `credits` (may be negative), `reason` | Adds an adjustment; returns the person's progress as `commitment_progress` shows it | `CommitmentAdjustmentsController#create` with `CommitmentAdjustmentPolicy#create?`, including its self-approval rule |
| `remove_commitment_adjustment` | `adjustment_id` | Removes it | `#destroy` with `CommitmentAdjustmentPolicy#destroy?` |

`commitment_progress` gains `adjustment_id` on each adjustment, only for viewers who may remove it.

### 5.8 Forms (`feature/mcp-forms`)

| Tool | Inputs | Effect / returns | Mirrors |
|---|---|---|---|
| `get_form` | `form_id` | Questions in order, with type, options and required. For a person: their response's state (not started, draft, submitted, signed) | `FormPolicy#show?`; the response by `FormResponsePolicy#show?` |
| `save_form_answers` | `form_id`, `person_id`, `answers` (`{ question_id: value }`), `submit?` | Saves a draft of the given answers. With `submit`, submits, as the person's Submit does. Answers mapped to person fields update them under §5.5's rules. Signature questions are refused | `FormResponsesController#update` and `#submit` with `FormResponsePolicy#update?` and `submit?`, so only those the page lets answer (the person, a guardian, or an organizer the policy allows) |
| `withdraw_form_response` | `form_id`, `person_id` | As the page's Withdraw | `#withdraw` with `withdraw?` |

Signing stays on the page: a signature is the person's own act.

### 5.9 Pages (`feature/mcp`, read)

| Tool | Inputs | Returns | Mirrors |
|---|---|---|---|
| `list_pages` | — | Pages the viewer can open: title, id, team, whether dynamic | `policy_scope(Page)` and `PagePolicy#show?`. Leave out content previews (BL-001) |
| `get_page` | `page_id`, `params?` (query string pairs) | The page as the viewer would see it, converted to plain text with tables kept as Markdown tables. Dynamic pages render their ERB as the viewer, exactly as a GET of the page does | `PagesController#show`. Render through the same path, so a dynamic page's own permission logic runs |

`get_page` runs stored ERB. That is what viewing the page already does, as the same user and with the same output. The tool adds no way to change the source. Renders that take longer than 10 s are stopped and reported. Output over 200 KB is cut, with `truncated: true`.

### 5.10 Remaining reads (`feature/mcp`)

| Tool | Inputs | Returns | Mirrors |
|---|---|---|---|
| `list_announcements` | `team_id?`, `limit?` | Announcements the viewer can see, newest first | `policy_scope(Announcement)` |
| `list_calendar_notes` | `from`, `to`, `person_id?` | Calendar notes in range | `policy_scope(CalendarNote)` |
| `list_questions` | `team_id?`, `open?` | Questions with reply counts | `policy_scope(Question)` |
| `get_question` | `question_id` | The question and its replies | `QuestionPolicy#show?`, replies as the page lists them |
| `list_event_checkin_fields` | `event_id` | The event type's check-in fields | Event in `policy_scope(Event)` |

## 6. Call log changes

- New fork migration (reversible): add `changed_records` jsonb to `mcp_tool_calls`, a list of `{ type, id }`. Bulk tools fill it; single-record writes fill both the old `changed_type`/`changed_id` and a one-item list. `dry_run` calls are logged with an empty list and `arguments.dry_run = true`.
- Mask `add_token`'s value (§5.4.2) and `create_person`/`add_login` passwords (none are stored; assert it in a test).
- The MCP Calls page shows the count of changed records and links each one to its page where one exists. Access is unchanged: admin only.

## 7. Tool descriptions and refusals

From the trial list: refusals read "Not found" (a record the viewer can't see), "Not allowed" (visible but not changeable) or an empty list (filtered). Keep all three, and say which applies in each tool's description, in one sentence. Every write's description names the page action it mirrors, so the client can tell the member where to do the same thing by hand. The server instructions add: "Changes need the member's own permission. If a change is refused, the member can't make it on the site either."

Setup help gains one line: after turning `mcp_write_enabled` on or off, refresh the connector and start a new chat.

## 8. Hooks

No new hookable models. Every write goes through an existing model, so its `CanBeHooked` events fire as on the page. Before building, check that `Person`, `User`, `Relationship`, `Token`, `TimeClockPunch`, `Membership`, `MembershipApplication`, `Event`, `Checkin`, `Signup`, `CommitmentAdjustment` and `FormResponse` are in the hook catalog. Report drift (BL-014); don't fix it on these branches. Bulk tools save each record the normal way (no `update_all`), so each fires its hooks.

## 9. Tests

As `mcp-spec.md` §12, for every new tool: admin, team manager, plain member on another team, guardian. Plus:

- Each write's refusal case returns "Not allowed" or "Not found" and changes nothing. Assert the record and PaperTrail versions are unchanged.
- `update_person` and `update_person_fields`: a field the page would drop is refused by name; a withheld field for a minor is refused; a partial set leaves other fields alone.
- `create_person` with `email`: login created, no password in the result, call log or Rails log.
- `clock_out`: `dry_run` changes nothing and lists the same punches a real run closes. A manager closes punches on an *added by admin* period of their team, but not on another team's. Caps at period end of day. Over 200 refuses.
- `move_signup` sends the same notices as the roster's Move (assert enqueued `SendEmailJob`s).
- `add_token`: duplicate value refused without naming the holder; value masked in result and log.
- `get_page`: a dynamic page renders as the viewer (a page that prints `current_user`'s name shows the token's user). A page the viewer can't open is "Not found". A slow render is stopped.
- Bulk tools: skipped records listed with reasons; one call log row with every changed record.

## 10. Phases

Ordered by how much routine work each one moves off the servers:

| Phase | Branches | Delivers |
|---|---|---|
| 1 | `feature/mcp`, `feature/mcp-person-fields` | Bulk-write support and call log migration (§2.2, §6). `create_person`, `update_person`, `find_duplicate_people`, `add_login` (§5.1, §5.2). `list_person_fields`, `update_person_fields` (§5.5) |
| 2 | `feature/mcp` | Time clock and tokens (§5.4), including `clock_out` |
| 3 | `feature/mcp-signups`, `feature/mcp-commitments`, `feature/mcp` | §5.6, §5.7, then §5.3's check-in and event writes, in parallel (disjoint branches) |
| 4 | `feature/mcp`, `feature/mcp-forms` | Relationships (§5.2), membership writes (§5.3), form answers (§5.8) |
| 5 | `feature/mcp` | Reads: §5.9, §5.10 |
| 6 | hbr/platform | Catalog and sample data updates (a period with open punches to clock out, a token, a pending membership application, a static and a dynamic Page), FORK.md rows, help text |

Each phase ships with writes still behind `mcp_write_enabled`, so a build can carry new tools before any are used.

## 11. Open questions

1. **Clock-out rule** (§5.4.1): follow the kiosk's All Periods (managers close punches on *added by admin* periods of their teams), as written, or the stricter per-punch `update?`? The stricter rule leaves non-admin managers unable to clock anyone out on the periods most organizations use for meetings.
2. **Rendered pages** (§5.9): include `get_page` at all? It's the only way a client can read report Pages, and it adds nothing a browser can't do. But its output is whatever the page's author wrote, including any data the page shows without checking.
3. **Token values** (§5.4.2): masked as written, or hidden entirely from `list_tokens`?
4. **Builders** (§3): after the trial, is there demand for creating sign-up sheets or form copies ("copy last year's sheet with new dates")? If so, copying an existing record is a much smaller tool than a builder.
5. **Announcements**: read only, as written, or also create? Creating one emails its audience.
6. **Which account connects.** Tools act as the connected member. A connector signed in as a member who isn't an admin can make few of these changes, and that is by design. Organizations that want an AI client to do admin work should connect it with an admin's account and keep the allowed badge narrow.
