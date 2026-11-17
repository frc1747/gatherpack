# Spec: My GatherPack

Status: rev. 5, 2026-11-15. Being built. Pitch: [`08-my-gatherpack.md`](../pitches/08-my-gatherpack.md). Code facts checked against integration `45405a02`. Decisions are in §12.

Rev. 5 (BL-044): checklist lines on Home say the answer, not the formula, and each fact shows once (§6.4); Your Checklists becomes My Season (§6.2); a new activity page (§7a) with its own branch and flag (§4); demo personas for both (§11). Mock-up: [Home card mock-up](https://claude.ai/artifact/4uzkEM4KVvamz6fwF7JYhg) (private).

Rev. 4: `MyGatherpack::Menu.place` lets a connector add menu placements safely (§5.2); shared queues appear on Home as one row (§6.2); Orders is planned as a connector (§4).

Rev. 3: the page says the site's title; checklists replace commitments on Home and Family (`feature/commitments-guardian-view` is dropped, per [`checklists-spec.md`](checklists-spec.md) §10.1); Phase 0 no longer blocks the build; sidebar additions use the slots seam.

Rev. 2: guardians get two additions, a ward's team events on the family page and a ward's per-person commitments (§7.3, decision 7).

Depends on the override seam in [`modern-skin-spec.md`](modern-skin-spec.md) §5. The screens use ordinary Bootstrap classes, so they work with or without the skin, but they should ship after it.

## 1. Goal

A member signs in and sees what they need to do next. Their menu holds what they use, and management tools sit apart. A guardian has one place for their children. The most common tasks work well on a phone.

The test is whether people can do these on their own phones without help:

| Task | Person | Today | After |
|---|---|---|---|
| Find out what you still owe | Member | Dashboard card, plus a profile tab | The home page, at the top |
| Sign up for Saturday | Member | Sign-ups, sheet, table | Home to sheet, in a phone list |
| Fill out a form that's due | Member | Dashboard card, then the form | Home to form, in a phone layout |
| Check your hours | Member | Time Clock, a table with small targets | A phone list with totals |
| See whether your children are caught up | Guardian | Each child's profile, then each tab | One family page |
| Sign a child's form | Guardian | Dashboard or Forms tab | Family page to form |
| Find a management tool | Manager | Long shared sidebar | Manage section, same names |

### 1.1 Non-goals

- New data or new permissions, except the guardian addition in §7.3.
- Replacing management screens. Rarely used admin pages stay desktop-first.
- Native apps, install and notifications. Those are in [`app-feel-spec.md`](app-feel-spec.md).

## 2. How it works today

- **Home.** `WelcomeController#index` renders `welcome/dashboard`: widget slots, `forms/_to_complete` (including "Waiting on You as a Leader"), shortcuts, announcements, `signups_summaries/_summary`, calendar, ledgers.
- **Menu.** `layouts/_sidebar` lists Dashboard and Sign Out, then `GatherPack::Features.nav_sections`, then the admin sections. `NavItem` is a struct of label, path and icon, so an item can't say who it's for. `ProfileTab` already has a `visible` proc.
- **Forms data.** `form_entries_for(person)` returns entries for the person and their wards; `forms_to_complete` selects those that are `to_do?`; `leader_todos` covers leaders. It loops over open and closed forms, and its cost grows with the form count.
- **Sign-ups and commitments data.** `SignupsSummary.new(user)` gives upcoming sign-ups and running commitments, and is empty when its feature is off.
- **Time clock.** `TimeClockPunchPolicy::Scope` gives admins all punches, managers their teams' and their own, and everyone else their own. `still_clocked_in` finds an open punch.
- **Guardians.**
  - `Person#wards` lists current wards.
  - `PersonPolicy` lets a guardian see a ward's profile.
  - `person_forms_tab?` and `ward_form_entries` cover forms, and `FormAccess` decides what they can do.
  - `SignupPolicy` and `SignupSheet#self_or_relative?` cover sign-ups.
- **Guardian limits that matter here:**
  - `EventPolicy::Scope` shows only events on the viewer's own teams, not their ward's.
  - `PersonCommitmentsPolicy` shows a ward's commitment to a guardian only when it's grouped through a relationship type (`group_relative_of?`), or the guardian organizes it.
  - `TimeClockPunchPolicy::Scope` never shows a ward's punches to a non-manager guardian.

## 3. Phase 0: watch people first

Before building, watch three or four members and a guardian do the §1 tasks on their own phones, with no prompts beyond the task. Note where each one hesitates or gets stuck. An organizer runs this, and the code work needs nothing from it except the result: a short list in order of pain, which goes in §9's order. If it contradicts anything in this spec, the spec changes. **It doesn't block the build:** the phone screens follow the §8.2 table order until there's a result.

## 4. Branches and flags

| Branch | Based on | Contents |
|---|---|---|
| `feature/nav-item-visible` | `upstream/main` | `NavItem` `visible` check. Upstream candidate, no flag needed; no item uses it yet |
| `feature/my-gatherpack` | `feature/view-overrides` + `feature/nav-item-visible` + `feature/sidebar-slots` | Flag, override folder, section registry, menu, home, family page, phone screens that are upstream-only |
| `feature/my-gatherpack-forms` | `feature/my-gatherpack` + `feature/forms` | Forms sections and the phone form |
| `feature/my-gatherpack-signups` | `feature/my-gatherpack` + `feature/signups-widget` | Sign-ups section and the phone sheet |
| `feature/my-gatherpack-checklists` | `feature/my-gatherpack` + `feature/checklists` | To-do items, Your Checklists and the family page rows, from checklists |
| `feature/my-gatherpack-activity` | `feature/my-gatherpack-family` (which carries the forms, sign-ups and checklists connectors) + `feature/checklists-connectors` (count items) + `feature/event-time-display` (`Event#time_kind`) | The activity page (§7a) and My Season's "Also this season" (§6.4) |
| `feature/my-gatherpack-orders` | `feature/my-gatherpack` + `feature/orders` | Planned, waits for Orders. To do rows, Your orders and menu placements ([`orders-spec.md`](orders-spec.md) §3.15) |
| Small `feature/*` branches | `upstream/main` | One per cleanup item (§8), each with its own backlog entry |

A `+` means the second branch is merged in, as a declared dependency. The core branch can't reference forms or sign-ups code, since upstream may not have them. So those sections are connectors, the same pattern as `feature/mcp-forms` and `feature/mcp-signups`.

Flags: `feature_my_gatherpack`, default off; `feature_my_gatherpack_activity` (§7a), default off, which needs `feature_my_gatherpack` on. With it off, all of today's screens and the sidebar are unchanged. Registered as `:my_gatherpack` with `position: 20`, so its overrides win over the skin's.

**Upstream files edited**

| File | Change |
|---|---|
| `lib/gatherpack/feature.rb` | `NavItem` gains `visible` |
| `app/views/layouts/_sidebar.html.erb` | Applies `visible?` when listing items |
| `app/views/layouts/application.html.erb` | The `<title>` line calls a helper (§5.2a) |
| `config/routes.rb` | `/family`, plus any phone-screen routes |

Everything else is a new file or an override. Overrides are listed in the drift lock ([`modern-skin-spec.md`](modern-skin-spec.md) §5.2).

## 5. Menu

### 5.1 `NavItem`

```ruby
NavItem = Struct.new(:label, :path, :icon, :visible, keyword_init: true) do
  def visible?(user)
    visible.nil? || visible.call(user)
  end
end
```

Existing registrations keep working. `_sidebar` skips items that aren't visible, and a section with none left loses its heading.

### 5.2 Groups

`app/view_overrides/my_gatherpack/layouts/_sidebar.html.erb` replaces the sidebar while the flag is on. The impersonation block, Sign Out, admin sections and version footer stay, and it renders the sidebar slots and root attributes (`feature/sidebar-slots`), so other features' controls and the permanent sidebar id still apply. `MyGatherpack::Menu` sorts the visible items:

| Group | Shown to | Items |
|---|---|---|
| (top, no heading) | Everyone | Home, Forms, Sign-ups, My Hours, Calendar, Teams, Announcements |
| Family | People with wards | Family |
| Section headings (since hbr.44) | Everyone | Every other item they'd see today, under the same headings as the plain sidebar (People, Time, Finance, Purchasing, Communication, Content), always open. No More list (Corey, 2026-11-17: "The more list sucks. Get rid of it.") |
| Manage | People who manage something (§5.3) | People, Teams, Time Clock, Badges, Tokens, Commitments, Ledgers, Budgets, Mailboxes, Pages, Widgets |
| Automation, Admin | Admins, unchanged | Variables, Reports, Hooks, Setup, Audit Log, MCP Calls |

- Groups are set in a table in the feature's initializer, keyed by path helper, so no existing feature registration changes. **An item not in the table goes under its section heading**, so a new feature can't vanish.
- A connector adds its own placements with `MyGatherpack::Menu.place(:some_path, manage: 35)`. Placements are stored apart from the table and merged when read, because connector initializers (`my-gatherpack-*.rb`) sort before `my_gatherpack.rb`, whose assignment of the table would otherwise wipe them. Once this exists, `MyGatherpack::ChecklistsMenuTable` moves to it and is deleted.
- "My Hours" points to the Time Clock page. For a manager, whose Time Clock lists their teams' punches too, it's `time_clock_punches_path` filtered to their own person.
- Items appear only if their feature is enabled, as today.

A menu never grants anything. Every destination still checks its own policy, and a person who types a URL gets what they'd get today.

### 5.2a The site's title

The page names the site, never the product. At the top of the sidebar on desktop: the site's logo and `Settings[:title]` ("Harrison Boiler Robotics"), as in the pitch's mockup, with the search box under it so search stays on every page. There's no top bar at `md` and up, so the title doesn't appear twice. On phones the same title is the one-line header (§8.1). The browser tab reads `Settings[:title]` alone on Home.

"My GatherPack" is the name of this feature in settings and docs. It appears nowhere on these screens. If `Settings[:title]` is blank, fall back to "GatherPack".

### 5.3 Who sees Manage

`MyGatherpack::Menu#manages_anything?` is true for an admin, for `person.manager?`, or when a registered check passes. Connector branches register theirs with `MyGatherpack::Menu.register_manager_check`: a Forms creator (the existing grant check), a commitment organizer (`Commitment.organizer_team_ids(person)`), a sign-up organizer (`SignupSheet.organizer_team_ids(person)`). The result is memoized for the request. Items within Manage are also filtered, so a Forms creator who manages no team doesn't see Tokens.

## 6. Home

### 6.1 Rendering

`app/view_overrides/my_gatherpack/welcome/dashboard.html.erb` replaces the dashboard. There's no new route or controller; `@shortcuts` and `@announcements` are already set. Widget slots stay in the same placements, so existing widgets keep showing.

The template asks a registry for sections:

```ruby
MyGatherpack.register_section(:forms, partial: "my_gatherpack/forms_section", column: :todo, position: 10,
  items: -> { ... }, # runs in the view; required for :todo, so the heading counts them
  enabled: -> { GatherPack::Features.enabled?(:forms) })
```

Connector branches register their own. A disabled feature's section doesn't appear, and neither does a section with nothing to show.

### 6.2 Layout

Matches the mockups in the pitch.

| Area | Content | Source |
|---|---|---|
| Site title | Logo and `Settings[:title]`, at the top of the sidebar (§5.2a) | Theme and settings |
| Heading | "Hi {first name}. You have {n} things to do." or "Hi {first name}. You're all caught up." | Count of to-do items |
| Status | "Clocked in since 4:32 PM", shown only when clocked in | `time_clock_punches.still_clocked_in`, `:time_tracking` enabled |
| To do | Forms due, checklist items the viewer can fix, waiting on you as a leader | `forms_to_complete`, `leader_todos`, `Checklists.checklist_for` |
| Coming up | Own sign-ups and events, soonest first, next 5 | `SignupsSummary#signups`, `policy_scope(Event)` |
| My Season (was Your Checklists) | Checklist items that aren't in To do, in words (§6.4): **In progress** (unfinished items the viewer can't fix right now, such as attendance), **Done** (collapsed to one line of titles, expandable) and, with the activity flag on, **Also this season** and a "See all your activity →" link (§7a). With nothing to do: "You're all set for now". A one-item checklist that another of the person's checklists already shows as a line is left out, and that line links to it | `SignupsSummary#checklists`, `MyGatherpack::Activity` (§7a) |
| Latest | Announcements | `@announcements` |
| Below | Shortcuts, ledgers, as today (no calendar: Coming up links to the full one) | Existing partials and markup |

Order inside To do: past due, then by nearest due date, then those with no date. Each row has one button with a specific label ("Fill out", "See shifts"). A ward's item names the ward ("for Maya"). Guardian wording appears only on those rows.

To do counts only what the viewer can act on: `to_do?` already means that for forms, and a checklist item counts only while it's unfinished and has a fix the viewer can use.

Work shared across a queue is one summary row ("12 lines to buy") rather than a row per thing, as leader to-dos roll up by form, so one person's queue doesn't swamp the list and the heading's count. Something active that needs nothing from the viewer isn't a to-do; it belongs in a `:side` section.

### 6.4 Checklist lines in words (rev. 5)

Each checklist item appears **once** on Home: in To do when it's unfinished and has a fix the viewer can use, otherwise in My Season. Its text answers "am I OK?":

| Result | Text | Example |
|---|---|---|
| Met | Title, a check, and what the person did, from the result's `confirmed` measure with its unit | "Attendance ✓ 44 h this fall", "Outreach ✓ 5 events" |
| Met, nothing measured | Title, a check, and the status word | "FIRST consent ✓ Signed" |
| Pending or not met, measured | The gap and, if the item has one, the due date | "3.5 more hours by Dec 31", "1 more shift" |
| Pending or not met, not measured | The status word | "Not started" |
| Exempt | Title and its exempt label, in Done | "Outreach · Rookie" |
| Pooled count (`group_relationship_type_id`) | The gap for the group | "1 more shift for your family" |

- No `x of y` text and no bars on Home. The full formula (for attendance: the share of hours held, the hours held so far, the person's hours, meetings left) moves to the item's detail, shown when the line is tapped. That's the detail the checklist page already renders (`instance.explain`).
- "This fall" and similar names come from the attendance rule group in force; with no named group, "this season".
- A ward's line is tagged with the ward's first name, as To do rows are.
- The wording lives in `MyGatherpackChecklistsHelper` (`feature/my-gatherpack-checklists`), replacing `my_gatherpack_season_count` and `my_gatherpack_season_percent` (the `x of y` text and the bar). The checklist page and the profile tab keep `x of y` and bars: they're for people reading the detail.

**What shows once, and where.** Sources are matched by reference, never by comparing numbers:

1. Checklist items first. They already carry forms (`form_complete` items), commitments (count items), sign-ups and check-ins (count sources) and attendance.
2. A form due appears in To do as a form row unless a checklist item of the viewer's (or the ward's) lists its id. Then only the checklist item shows.
3. Coming up lists places and events, not requirements. A to-do's action ("Sign up: Sat Nov 21") links to the sheet.
4. "Also this season" (§7a) lists the person's own check-ins by event type, only for event types and sheets that **no** count item covering the person counts. Meeting hours are never in it: attendance covers meetings.

**My Season for guardians** (Corey, 2026-11-15). When the viewer is a guardian and more than one person has My Season lines, My Season shows one block per person: the viewer first, headed "You", then each ward by first name. Each block has its own In progress list, its own collapsible Done and its own "You're all set for now". Inside a person's block a line doesn't repeat the person's name; a ward's line links to that ward's checklists page.

**The leak rule.** Home, My Season and the activity page never name or link a checklist that doesn't cover the person they're about. A person the checklist leaves out sees "Not required for you", never its title.

### 6.3 Performance

The home page combines several features, and `form_entries_for` and team lookups are slow on large sites. Budget: on the demo database, as a member and as a guardian with 2 wards, home must not take longer than today's dashboard does for the same person by more than 25%. Measure before building, and again at each section. If forms are the bottleneck, fix `form_entries_for` itself, which helps today's dashboard too. Late-loading sections are a fallback, with placeholders as in [`app-feel-spec.md`](app-feel-spec.md) §5.4.

## 7. Family page

### 7.1 Route and access

`GET /family`, `FamilyController < InternalController`, a new `FamilyPolicy` with `show?` true when `person.wards.exists?`. Someone with no wards gets redirected to home, with no error. The menu item uses the same check. It isn't a place to manage relationships.

### 7.2 Content

One card per ward, in name order, with a heading line ("1 thing needs you" or "All caught up"):

| Row | Source | Action |
|---|---|---|
| Forms | `ward_form_entries`, `to_do?` first | Existing form page |
| Sign-ups | `Signup.active` where `person`, `on_behalf_of` or `signed_up_by` is this ward, on sheets the viewer may see | Existing sheet |
| Checklists | `Checklists.status_for(checklist, [ward], viewer: user)`, which applies each item's "who sees it" | Existing checklist page |
| Upcoming events | Events on the ward's teams, next 5 (§7.3) | Event page only if `policy_scope(Event)` already includes it |

Below the cards, "What your family owes" shows pooled count items, with a link to open shifts.

Forms, sign-ups and checklists go through policies and helpers, so those pages and this one always agree. A test checks each of those rows against the same person's profile. Events are the one row with its own rule (§7.3).

### 7.3 A guardian addition

Today's rules hide a ward's team events, which the mockup shows. Decided 2026-11-04: guardians should see them. This covers current wards only (`Person#wards`), so it ends when a guardianship does.

A ward's per-person counts aren't a separate addition any more. Each checklist item has its own "who sees it" setting ([`checklists-spec.md`](checklists-spec.md) §10.1), and the family page follows it.

1. **A ward's team events.**
   - `EventPolicy::Scope` limits a guardian to their own teams' events, and it **isn't widened**. That scope also decides which events are listed elsewhere, and an event page shows its check-in list, with other families' children on it. A guardian needs to know when and where, not who else came.
   - Instead, `MyGatherpack::WardEvents` selects upcoming events on `ward.all_teams`, and the family page shows title, time and place only. The row links to the event page only when the viewer's `policy_scope(Event)` already includes that event.
   - This depends only on `feature_my_gatherpack`, because the family page is the only thing it changes.

Time clock punches stay out. `TimeClockPunchPolicy::Scope` is unchanged, so hours on the family page are what a commitment counts. The mockup's meeting hours are that kind.

## 7a. Activity page (rev. 5)

"What have I done this season?", next to Home's "am I OK?". Own records only, so nothing about anyone else's records or any checklist the person isn't on can leak.

### 7a.1 Route, access and flag

- `GET /activity` for yourself and `GET /activity?person=<neat id>` for a ward. `MyGatherpack::ActivityController < InternalController`, `ActivityPolicy#show?`: the person themselves, or a current guardian of theirs (`Person#wards`). Anyone else, including admins (who have the profile), is redirected to their own page. It isn't a reporting tool.
- Flag `feature_my_gatherpack_activity`, default off. With it off the route redirects home and Home shows no link or "Also this season". Linked from the menu ("My activity", top group, right after Home), from a full-width button under My Season and, for guardians, from each ward's card on the family page.

### 7a.2 Season

The season runs from `Settings[:my_gatherpack_season_start]` (month and day, default May 1, registered with `Settings.register`) for one year. The page shows the current season, with a select for earlier seasons that hold records. A ward's season is the same as the viewer's.

### 7a.3 Content

Two separate concerns (Corey, 2026-11-15): what the person has done for the team, and what their checklists require. The page shows them apart.

| Block | Content | Source |
|---|---|---|
| What you've done ("What they've done" on a ward's page) | Jump links to each section when there are two or more. Meetings as one line, own page only, while time tracking is on ("Meetings: 14 of 19 · 42.3 h"). Then one section per event type with an event in the season, with a total ("Outreach: 2 events · 7 h") and its events newest first: date, name, place, hours, "Checked in" or "Signed up". A line may say "Counts toward <item>" for a checklist that covers the person; a section may say "Not required for you". Forms and punches aren't listed. With nothing: "Nothing yet this season." | Non-meeting check-ins (`Checkin`) on events in the season, plus fulfilled sign-ups at events with no check-in, on sheets the viewer can see, one line per event; event hours are `end_time − start_time` for `time_kind: timed` events; an all-day event (or a timed one from midnight to midnight) shows "All day" and adds no hours; "Counts toward" only when the event is in the item's commitment teams and period; punches for the meetings line |
| Requirements | Each covering checklist, its overall in words, linked (side column) | `Checklists.checklist_for` with `viewer:` |
| Coming up | Upcoming sign-ups | `SignupsSummary#signups` |

At phone width the blocks stack in one column: What you've done, Requirements, Coming up. Jump links are 44 px targets.

### 7a.4 A ward's page

Each row goes through the policy that already governs it, and §7.3 doesn't widen anything:

- Check-ins and events: the event's title, date, type and place only, the same fields the family page shows for a ward's upcoming events (§7.3), and no link unless `policy_scope(Event)` already includes the event. Past events are new here: the guardian learns which events the ward checked in at, nothing about anyone else.
- Sign-ups and forms: as the family page.
- **Punches stay out** (decision 7). The meetings line is left out; attendance shows on the Requirements card.
- Requirements: `Checklists.status_for(checklist, [ward], viewer: guardian)`.

### 7a.5 "Also this season" on Home

`MyGatherpack::Activity.uncounted(person, season)` returns event types (with event count and hours) that have a check-in by the person in the season and that no count item covering the person counts (§6.4, point 4). My Season shows them as "Outreach: 2 events · 6 h". The activity page uses the same object, so the two always agree.

## 8. Phone screens and cleanup

### 8.1 Phone frame

While the flag is on, below the `md` breakpoint:

- The `_navbar` override shows a one-line header with the site name, plus search.
- A fixed bottom tab bar replaces the top-left menu button: Home, Forms, Sign-ups, Hours and Menu. Guardians get Family in the first position in place of Hours. Menu opens the existing off-canvas sidebar.
- The tab bar renders in the `_navbar` override. It's fixed, so its place in the document doesn't matter, and the layout itself doesn't need an override.
- Breadcrumbs are hidden on phones. Page titles do that work.
- Tap targets are at least 44 px tall in these screens.
- The tab bar respects `safe-area-inset-bottom`, and pages get matching bottom padding.

The kiosk layout doesn't get any of this.

### 8.2 Top four tasks

Each is one override, built in the order Phase 0 sets. Each must keep the original's fields, policy checks and Turbo behavior.

| Screen | Original | Change |
|---|---|---|
| Filling out a form | `forms/_form` and related | One column, large controls, a sticky Save at the bottom |
| Claiming a shift | `signup_sheets/show` | Dates as sections, positions as rows with places left and a Sign up button; table above `md` only |
| My hours | `time_clock_punches/index` | One person's total for the selected Time Clock Period, or the period running today, at the top; then punches as rows; edit actions behind a row tap for those allowed |
| Calendar | `calendar/index` | Opens on List view, with a toolbar that fits 390 px |

Where a small upstream edit does the job better than an override (for instance, the calendar toolbar config), prefer the edit and record it.

### 8.3 Cleanup items

Each is its own backlog entry and small branch, not part of the flag, and most are upstream candidates:

- People: collapse the search form behind a Search button at phone width. The page is about 10,500 px tall today.
- Remove required-field asterisks from search forms.
- Wrap the 11 of 24 table templates that lack `table-responsive`.
- Forms: separate My Forms from Manage Forms, so a member's page doesn't run straight into a manager's.

Others come from Phase 0. Duplicated screens are removed only with a list of what links to them.

## 9. Phases

0. **Watch people** (§3).
1. **Menu and `visible`** (§5). The largest visible gain for the least work, and every later part builds on it.
2. **Home** (§6), with its connectors.
3. **Phone frame** (§8.1).
4. **Family page** (§7).
5. **Phone screens** (§8.2), one at a time, in Phase 0's order.
6. **Cleanup items** (§8.3), at any time. They don't depend on the flag.

## 10. Tests

- **`NavItem`:** nil `visible` shows; a false proc hides; an empty section loses its heading.
- **Role matrix for the menu.** Member, guardian, team manager, Forms creator, organizer, admin, and an impersonated member: each sees exactly the expected groups. An unknown item lands in More. A `Menu.place` entry survives the core's table being assigned after it.
- **Destinations are still guarded.** A member with no Manage section who requests a manager page gets what they get today.
- **Home:** each section shows or hides by feature flag; empty state; sort order; the ward label; widget slots still render; nothing shown to one person leaks to another in a shared fixture world.
- **Family:** no wards redirects; each ward shows only policy-allowed rows; an expired guardianship removes that ward's events and checklists; a ward's event shows title, time and place but no check-ins, and links only if the viewer can already reach it; a ward's team event doesn't appear in the guardian's events list or calendar.
- **Guardian visibility:** the family page shows a ward's checklist item only when that item's "who sees it" allows it; a non-guardian relative and a former guardian see nothing.
- **Site title:** the sidebar brand, the phone header and the browser tab show `Settings[:title]`; the words "My GatherPack" appear in no rendered page.
- **Query budget** (§6.3), as a measured check with the demo database, not a unit test.
- **Phone:** system tests at 390 px for each of the top four tasks, completing the task through to saved data, with the flag on and with the skin on and off.
- **Rollback:** flag off renders today's dashboard and sidebar.
- **Checklist lines (§6.4):** met with a measure shows what the person did and no threshold; unmet shows the gap and due date; exempt sits in Done with its label; a pooled count says "for your family"; no `x of y` or bar on Home, while the checklist page keeps them; each item appears once (To do or My Season, never both).
- **Shows once (§6.4):** a form listed by a checklist item isn't also a form row; an event type counted by a count item covering the person isn't in "Also this season"; meeting hours never are.
- **Leak rule:** a person a checklist doesn't cover never sees its title or a link to it on Home, My Season or the activity page ("Not required for you").
- **Activity page (§7a):** own page; a guardian's ward page; a non-guardian, a former guardian and an admin are redirected; a ward's page has no punches; season boundaries (a record on the start date belongs to the new season); flag off redirects and hides the link and "Also this season"; Home and the activity page agree on "Also this season".

## 11. Hooks and sample data

**Hooks.** No new models, so no catalog entries, and no new events. These screens read data and hand off to existing pages, whose hooks fire as usual.

**MCP.** Tools match the app. `get_person` gains the ward's upcoming events for a guardian, with the same three fields, in a connector branch once the family page ships.

**Sample data.** `fork/sample_data/features/my-gatherpack.rb` makes one Northwind guardian with two wards: one child with a form due and a shift to claim, one all caught up. It also adds a member clocked in with a commitment partly met, and a Forms creator who manages no team, so each state in §10 can be viewed. Connector branches add their records to their own files. `feature/my-gatherpack-activity` adds, in its own file, check-ins across three event types and punches across two seasons for one member, so §7a's totals, filter and season select all show something.

**Demo personas** (rev. 5, `fork/demo_db/personas.rb` on `hbr/platform`; the help site's captures use these):

| Persona | Email | Shows |
|---|---|---|
| Demo Member (exists; holds 2027 Season Rookie) | `demo.member@example.invalid` | The rookie: not on Outreach, two Outreach check-ins, so "Also this season" and "Not required for you" |
| Sam Student (new, Class of 2028) | `demo.student@example.invalid` | Behind: attendance short with a gap and date, no outreach, no concessions; a form that a checklist item lists, so it shows once |
| Demo Veteran (new, Class of 2027) | `demo.veteran@example.invalid` | All done: every item met, two upcoming sign-ups, "You're all set for now" |
| Demo Parent (new in `personas.rb`; the hosted demo had one added by hand) | `demo.parent@example.invalid` | Guardian of Demo Member and, new, Sam Student, through the pooling relationship, so the family owes Concessions together |

Plus, for [BL-045](../backlog/BL-045-checklist-rule-wording.md): one sign-up sheet with a checklist rule that Sam Student is covered by but hasn't finished, and that Demo Member isn't covered by. The rule's checklist mustn't be one the sheet itself counts toward (or its warning shows instead).

## 12. Decisions

1. **The menu changes what is shown, never what is allowed.** Hiding a link isn't access control, and tests check the destination too.
2. **Nothing becomes unreachable.** Items that aren't in the short list go under their section heading, and unknown items too.
3. **Keep familiar names in Manage.** Managers know these words. "My Hours" is the one new name, and it's a link to the same page.
4. **The home replaces the template, not the route.** `root_path` still works, and the flag restores the original.
5. **Sections register themselves.** That keeps the core free of forms and sign-ups code, and is how a future feature gets a place on the home page.
6. **Family is read and link, not a second way to act.** Actions open the existing page, so there's only one path for each, and one set of rules.
7. **One deliberate addition for guardians** (§7.3). A ward's team events appear as title, time and place on the family page, with the event scope unchanged, because event pages list other children. Per-person counts follow each checklist item's "who sees it". Time clock punches stay out.
8. **No personalization settings for the menu.** One well-chosen list beats several ways to arrange it.
9. **The page says the site's title, not "My GatherPack"** (§5.2a). Decided 2026-11-08.
10. **Announcements on phones** are under Communication and on Home.
11. **People stays under its People heading** for members.
12. **Home answers, the activity page explains** (rev. 5, Corey 2026-11-15; rev. 6: the activity page shows what was done apart from what's required). Home says whether you're OK in words; numbers that need the formula live in the item's detail and on the activity page. One card, not a second stats section.
13. **Each fact shows once, matched by reference** (§6.4). Checklists first, then loose forms, then sign-ups as the calendar, then activity no checklist counts.
14. **Attendance covers meetings; everything else is activity** (rev. 5). Meeting hours are never in "Also this season".
15. **Forms stay in To do on Home** (rev. 5). The separate Forms to Complete card is already replaced on Home (§6.2); a form a checklist lists shows only as that checklist item.
16. **The activity page is own records only** (rev. 5). A ward's page adds one thing to §7.3: which past events the ward checked in at (title, date, type, place). Punches stay out for guardians.
