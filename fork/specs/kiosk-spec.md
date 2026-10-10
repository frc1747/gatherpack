# Spec: Time Kiosk Improvements

Status: draft rev. 2, 2026-10-09. Phases 1–3 are planned. Phase 4 (kiosk devices) is recorded here but on hold until Corey starts it.

This spec lives on `hbr/platform`, not on a feature branch. It covers several branches, and some of them may go upstream, where a spec that mentions HBR must not appear.

Rev. 2 includes a code review and a fact check against the installed gems (Rails 8.1.4, simple_form 5.4.1, turbo-rails 2.0.23 / Turbo 8.0.23, paper_trail 17.0.0).

## 1. Goal

Make the time kiosk faster to use, safe to leave unattended, and able to remind people of things when they scan in.

1. **Auto clock-in.** An admin can lock the kiosk to one time clock period. Scanning a card clocks the person in right away and shows their profile as confirmation, with no extra click. Off by default.
2. **Return to Welcome.** The profile clears itself after a configurable number of seconds. Off by default.
3. **Reminders at the kiosk.** A widget can appear on the profile that pops up after a scan, showing that person's reminders and alerts (for example, items from the Eligibility Report).
4. **Safety.** The kiosk acts only for the person whose card was just scanned, and only chosen accounts can open it. Later (Phase 4), the kiosk becomes a registered device instead of a signed-in person.

### 1.1 Non-goals

- Changing how punches, periods or hours are calculated.
- Clocking out on a second scan. A second scan shows the profile. Clocking out stays a button press, so a double scan never ends a shift.
- Reminder content in code. Reminders are a widget that admins write and change (Phase 3).
- Fixing kiosk crashes for punches with no period. That is BL-012, its own upstream bug branch.

## 2. How the kiosk works today (upstream `86ab397`)

| Piece | Where | What it does |
|---|---|---|
| Route | `config/routes.rb:95-97` | `get`, `post` and `patch "time_kiosk"`, all to `TimeKioskController#index`. Drawn only when the `time_tracking` feature is on. |
| Controller | `app/controllers/time_kiosk_controller.rb` | One action. `params[:time_kiosk][:tool]` picks what happens: `find_token`, `punch_in`, `punch_out`, `punch_out_period`, `punch_out_all`. Replies with a Turbo Stream replacing `#kiosk-content`, or the full page. |
| Model | `app/models/time_kiosk.rb` | `ActiveModel` holder for the params. `person` is `Person.find_by(id: person_id) \|\| token&.tokenable`, so a `person_id` from the browser wins over the card, and a Hook's token returns a Hook. |
| Views | `app/views/time_kiosk/` | `_kiosk`: the token box on the left; on the right, the flash and then `render @time_kiosk.tool`. Plus `_welcome`, `_found_person` and `_not_found`. `_period_select_form` is unused. |
| Layout | `app/views/layouts/kiosk.html.erb` | Header with the site logo linking to `/`, and the signed-in user's name and photo. It requires `current_user.person`. |
| Access | `ApplicationController#check_for_user` | Any signed-in user. No role check and no `authorize`. |

After a scan, `_found_person` shows:
- The person's photo and their hours per period.
- A Clock In button for each period the person can use and that is current. The rule is the query at `time_kiosk_controller.rb:17`: the period's team is one of `person.all_teams`, or it has no team, and `start_time <= now AND end_time >= now`. Both columns are dates, so a period stops being current at midnight at the start of its last day.
- "Start Unassigned", which does nothing: `time_clock_period_id` is nil, and `punch_in` only creates a punch when a period is found.
- The person's open punches, each with Clock Out.
- For managers (`@person.manager?`, the **scanned** person), a **Manager** button that opens Time Management: mass clock-out per managed period, and across all of them.

Clocking in returns to Welcome right away, so the person never sees a confirmation.

Kiosk punches are created with `created_by: "kiosk"`. This is a non-persisted attribute that makes `TimeClockPunch#permission_check` skip both the team check and the period's `permission` level. Only `valid_times` applies.

### 2.1 Who runs the kiosk now

Checked in production on 2026-10-09: all 48 punches made at the kiosk in the previous 30 days were created under one of two admin accounts. The kiosk browser is signed in as an admin.

### 2.2 Problems

1. **The browser decides who the kiosk acts for** (`time_kiosk_params` permits `person_id`, `time_clock_punch_id`, `time_clock_period_id`).
   - `punch_in` clocks any `person_id` into any period, including other teams' periods and `added_by_admin` periods, because `created_by: "kiosk"` skips the permission check. Repeating the request stacks open punches.
   - `punch_out` closes any punch by id. Sent for a punch that is already closed, it moves the `end_time` to now, which rewrites finished history.
   - `punch_out_period` checks edit rights on the period, but for whatever `person_id` it's sent. Sending an admin's person id closes every open punch in any team period. For a person with no login it raises a 500.
   - `punch_out_all` has no check at all. Sending an admin's person id closes every open punch in every team period.
   - **All of these also work over GET,** which has no CSRF protection, so a link or image on another page can trigger them in a signed-in browser.
2. **`tool` from the browser is passed to `render`.** Any string reaches `render @time_kiosk.tool`. Unknown names are a 500, and a name with a `/` renders other partials. Scanning a Hook's token sets `tool = "found_hook"`, which has no partial, so it is also a 500.
3. **Anyone signed in can open the kiosk.** A student can open `/time_kiosk` on a phone.
4. **There's no limit on card lookups.** Cards are `1747` plus 8 random digits.
5. **An admin session sits on a shared screen.** The header logo links to `/`.

Phase 1 fixes 1, 2 and 4. Phase 2's kiosk users setting fixes 3. Step 0 reduces 5, and Phase 4 removes it.

## 3. Phases and branches

| Phase | Branch | Base | Upstream intent | Contents |
|---|---|---|---|---|
| 0 | none | | | Sign the kiosk in with a plain account: no admin, no manager, and not on any roster team, so it stays out of the reports. Done by hand on the shop computer. This *reduces* problem 5. The account can still reach a basic member's dashboard through the logo. |
| 1 | `feature/kiosk-scanned-person` | `upstream/main` | Candidate (bug fix), only once Corey confirms | §4 |
| 2 | `feature/kiosk-auto-clock-in` | `upstream/main` | Undecided; written to upstream standards and naming | §5 |
| 3 | `feature/widgets` (existing) | `upstream/main` | Fork-only, like widgets | §6, then the content in §7 |
| 4 | `feature/kiosk-devices` | `feature/kiosk-auto-clock-in` | Undecided | On hold (§8) |

**Keeping Phases 1 and 2 independent.** Both edit `time_kiosk_controller.rb`. To keep the rebuild clean:

- **Phase 1** edits only the punch tools, the param list and the access checks at the top of the class (§4.5). Its class-level lines (`rate_limit`, the POST-only check) go directly after `layout "kiosk"` (line 2).
- **Phase 2** adds one call inside `find_token` and one `before_action` line. The `before_action` goes directly before `def index` (line 4), so the existing blank line 3 separates it from Phase 1's lines. Git conflicts on edits that touch each other, so a different line is not enough: at least one unchanged line must sit between the two branches' edits. The same applies in `_kiosk.html.erb` (§5.5).
- **The period rule.** Phase 1 doesn't extract the "current and can use it" query. `TimeKiosk::AutoClockIn` keeps its own copy in its new file.
- **Tests.** Phase 1's tests go in the existing placeholder `test/controllers/time_kiosk_controller_test.rb`. Phase 2's go in new files only.
- **Signed reference.** Phase 1 creates it in `TimeKiosk` or the view, never in `find_token`.

If they still conflict in a trial rebuild, rebase Phase 2 onto Phase 1 and declare the dependency. While Phase 1 sits behind an open upstream PR it can't be rebased (STRATEGY, Sync step 4), so Phase 2 would stay on Phase 1's old base.

`FORK.md` gets a row for each of Phases 1 and 2 when their branches get their first commit.

## 4. Phase 1: Act only for the scanned card

### 4.1 Signed reference

The profile's buttons, including those in the Manager window, carry a **signed, short-lived reference to the scanned person** instead of `person_id`:

```ruby
person.signed_id(purpose: :time_kiosk, expires_in: 5.minutes)
```

It is created by `TimeKiosk#person_ref`, which is called from `_found_person`.

The punch tools resolve the reference with `Person.find_signed(ref, purpose: :time_kiosk)`. Use `find_signed`, not `find_signed!`: it skips the neat_ids `find` override and returns nil for a reference that is missing, forged, expired or for another purpose. When it returns nil, the tool does nothing and the kiosk shows Welcome with "Please scan your card again."

The fact check found two properties of the reference:
- **It is signed, not encrypted.** The person's UUID can be read from it. That's fine, since UUIDs aren't secret.
- **It can be replayed until it expires.** The rules in 4.2 limit what a replay can do: a second `punch_in` meets the open-punch check, and a second `punch_out` refuses a closed punch. The worst case is clocking the same person back in after they clocked out, within the reference's 5 minutes.

`TimeKiosk#person` no longer takes `person_id`. It returns the token's `tokenable` only when that is a `Person`. `person_id` is removed from `time_kiosk_params`, and a `person_ref` param is added.

### 4.2 Tool rules

| Tool | Today | After |
|---|---|---|
| `punch_in` | Any `person_id` into any period, over any HTTP method | POST only. The signed person, into a period that passes the profile's rule (§2), and only if the person has no open punch in that period, of any age. This matches the profile, which already hides a period's Clock In button while the person has an open punch in it (`time_kiosk_controller.rb:19`). "Start Unassigned" stays a no-op, as today (§4.4). |
| `punch_out` | Any `time_clock_punch_id`, open or closed | POST only. The punch must belong to the signed person and still be open. |
| `punch_out_period` | `person_id`'s edit rights on the period. 500 when that person has no login | POST only. The signed person must have a login and pass `TimeClockPeriodPolicy#edit?` for the period. A person without a login is refused. |
| `punch_out_all` | Any `person_id`, no check | POST only. Uses the signed person's managed periods, and requires a login, as for `punch_out_period`. |
| `find_token` | Any method | Any method, as today (it only reads). Rate-limited (§4.3). |

The five-minute lifetime covers reading the screen and opening the Manager window. Every new scan issues a fresh reference.

### 4.3 Tool allowlist, Hook tokens and rate limit

- **Incoming tools.** The only accepted values are `find_token`, `punch_in`, `punch_out`, `punch_out_period` and `punch_out_all`. Anything else is treated as `welcome`.
- **Rendered tools.** The view renders only `welcome`, `found_person` or `not_found`.
- **Hook tokens.** A token that belongs to a Hook, or to anything other than a Person, shows `not_found`. (Running a hook from a card is unfinished upstream: no partial exists, and `token - activate` is listed in `Hook.catalog` but never fired.)
- **Rate limit.** Rails 8.1's built-in `rate_limit`: 60 lookups per minute per signed-in user, which a crowd arriving at once won't reach. The defaults don't fit, so spell out each option (`actionpack-8.1.4/lib/action_controller/metal/rate_limiting.rb`):
  - **Only `find_token`.** The controller has a single action, so `only: :index` would cover every tool. Use `if: -> { params.dig(:time_kiosk, :tool) == "find_token" }`, which is passed through to `before_action`.
  - **Per user.** The default key is the IP. Use `by: -> { current_user.id }`.
  - **What happens at the limit.** The default raises a 429. Use a `with:` lambda that shows Welcome with "Too many scans. Wait a minute and try again."
  - **The store.** Production uses Solid Cache, which counts across both workers. Test and development use `:null_store`, where `rate_limit` silently does nothing. Use `store: Rails.env.test? ? TEST_STORE : Rails.cache`, with a class-level `MemoryStore` for tests. Don't pass a `MemoryStore` unconditionally: in production it would count per process.
- **Dead code.** Delete the unused `_period_select_form.html.erb`.

### 4.4 Left alone

- **Crashes from punches with no period** (`_found_person.html.erb:63, 92`). These are BL-012, a separate small upstream PR.
- **"Start Unassigned" does nothing.** Making it work would trigger those same crashes. It belongs with BL-012, where both can be decided together. Phase 1 changes only its URL.
- **Kiosk punches skip the period's `permission` level** (`created_by: "kiosk"`). Upstream does this on purpose. Phase 1 now enforces the team rule because the profile already offers only those periods, but the permission level stays ignored.
- **The kiosk looks tokens up with `Token.find_by(value:)`,** not `Token.find_by_rfid`, so `5700…` hex reads from the second RFID reader type don't match. Out of scope. Mention it upstream with the PR if Corey wants.

### 4.5 Upstream files touched

- `app/controllers/time_kiosk_controller.rb`: the punch tools, the params, the allowlist, `rate_limit`, and the POST-only checks
- `app/models/time_kiosk.rb`
- `app/views/time_kiosk/_found_person.html.erb`: button URLs only
- `app/views/time_kiosk/_kiosk.html.erb`: the rendered-tool allowlist
- `app/views/time_kiosk/_period_select_form.html.erb`: deleted
- `test/controllers/time_kiosk_controller_test.rb`: today an empty placeholder

### 4.6 Tests

- A scan shows the profile. Its buttons carry `person_ref` and no `person_id`.
- `punch_in`:
  - With a valid reference, creates the punch.
  - Creates nothing when the reference is forged, expired or for another purpose, when only a `person_id` is sent, or when the request is a GET.
  - Creates nothing when the period isn't one the person can use, or when they already have an open punch in it.
- `punch_out` refuses a punch belonging to someone else, a closed punch, and a GET.
- `punch_out_period` and `punch_out_all`:
  - Work with a manager's reference.
  - Refuse a non-manager's reference, a bare `person_id`, and a manager with no login (no 500).
- An unknown `tool`, or one with a `/`, renders Welcome. A Hook's token renders "not found".
- The 61st `find_token` in a minute from the same user is refused, using the test's memory store.

### 4.7 Upstream

A bug fix for any GatherPack site. Before any upstream issue or PR, Corey confirms the topic and the wording. Frame it as "the kiosk trusts ids from the browser". Don't name production accounts or HBR.

## 5. Phase 2: Auto clock-in, return to Welcome, kiosk users

### 5.1 Settings

Three settings go in the existing "Time Clock" group in `lib/settings.rb`, placed right after `time_clock_max_hours` and away from the end of the file, where person-fields and forms append theirs. Each default leaves the kiosk as it is today.

| Key | Type | Label | Default | Description on the Settings page |
|---|---|---|---|---|
| `time_kiosk_auto_period` | `time_clock_period_select` | Kiosk: clock in automatically to | `""` (off) | When set, scanning a card at the kiosk clocks the person in to this period right away. Leave as Off to have people choose. |
| `time_kiosk_return_seconds` | `integer` | Kiosk: return to Welcome after (seconds) | `0` | After a scan, go back to the Welcome screen after this many seconds. 0 keeps the person's screen up until the next scan. |
| `time_kiosk_users_team` | `team_select` | Kiosk: who can open the kiosk | `""` (anyone signed in) | Only admins and direct members of this team can open the time kiosk. Leave blank to let anyone signed in open it. |

**Inputs.** Two new simple_form inputs in `app/inputs/` provide the dropdowns. simple_form finds `TimeClockPeriodSelectInput` and `TeamSelectInput` from the `as:` type, the same way `CurrencyInput` and the others work, so `settings/index.html.erb` doesn't change. Both subclass `SimpleForm::Inputs::CollectionSelectInput`. Because the settings form has no object:
- Before calling `super`, set `options[:selected]` from `input_html_options.delete(:value)`. Removing `value` also stops it rendering as a stray attribute on the `<select>`.
- Provide the "off" choice as the first collection entry, `["Off", ""]` or `["Anyone signed in", ""]`, with `include_blank: false`. Otherwise simple_form adds a second, unlabeled blank option.
- The period list shows periods that haven't ended, plus the currently stored one even if it has ended, so the page shows what is set.

**Values.** The stored value is the record id as a string. Read it with `.presence`. A setting pointing to a deleted period or team counts as off.

**Reading settings fresh.** Upstream's `Settings` caches each value per process at boot, and saving updates only the process that handled the save. Production runs 2 Puma workers (`WEB_CONCURRENCY` defaults to 2), so a change would reach about half the scans until a restart. The kiosk code reads these three keys straight from the file on each request, in a small `TimeKiosk::Config`. It uses its own `PStore.new("storage/settings.pstore", true)`, not `Settings.instance.store`. Upstream's store is not thread-safe, so a second Puma thread entering a transaction raises "nested transaction" instead of waiting. The thread-safe flag adds a mutex, and the PStore file lock still covers other processes. Test: two threads reading at once don't raise. The upstream bug itself is BL-013.

**Flag.** The settings are the feature flag: blank or 0 means off. No `GatherPack::Features` entry is needed.

### 5.2 Auto clock-in

`TimeKiosk::AutoClockIn` (`app/models/time_kiosk/auto_clock_in.rb`) takes the scanned person and returns a result: the period, the punch (created or found) and a banner. `TimeKioskController#index` calls it in `find_token`, after the person is found and before the profile's periods and open punches are loaded, so the profile shows the new punch.

The period must pass the profile's rule (§2), checked with AutoClockIn's own copy of the query (§3). "Today" is the site's time zone (`set_time_zone` is an `around_action`).

| Situation | Result | Banner (`flash.now` key) |
|---|---|---|
| Setting off, or the period deleted | Nothing. Profile as today. | none |
| Period not current, or the person can't use it | Nothing. Profile as today, with its buttons. | none |
| Open punch in the period that started today | No new punch. | `notice` (blue): "You're already clocked in to *Period* (since 6:02 PM)." |
| Punch in the period that started today and is closed | No new punch. The person can still press Clock In. | `notice`: "You clocked out of *Period* at 8:00 PM. Use Clock In below to clock back in." |
| Open punch in the period from an earlier day (missed clock-out) | No new punch, matching the manual rule (§4.2). The person clocks the old punch out on the profile, then presses Clock In. | `warning` (yellow): "You're still clocked in to *Period* from Thu, Oct 8. Clock out below, then clock in, and tell a mentor so they can fix the old punch." |
| No punch in the period today | Create the punch as the Clock In button does (`start_time: Time.current`, `created_by: "kiosk"`). | `success`: as above |
| The punch fails validation | Nothing. | `danger` (red): "Couldn't clock you in. Please use the buttons below." |

`_kiosk.html.erb` already shows `flash.now` in the Turbo Stream response, and `flash_to_class`/`flash_to_icon` already know `notice`, `success` and `danger`, so no view change is needed.

**Mentors** are treated like everyone else (decision 2). A mentor on the period's team who scans to reach the Manager button is clocked in if they have no punch in the period today, and their mass clock-out then closes it with everyone else's. A mentor who already clocked in or out that day gets no new punch.

**Missed clock-outs.** Neither the manual path nor auto clock-in opens a second punch beside a forgotten one. Clocking the old punch out (the person's Clock Out, or a mass clock-out) ends it at now, capped at the end of the period's last day. That makes it a multi-day punch, which the Flagged page catches as longer than `time_clock_max_hours`, where a mentor corrects it. This is existing upstream behavior. Auto clock-in neither causes nor fixes it.

**With Phase 1** the profile's buttons still carry the signed reference, so the person can clock out or into another period from the same screen.

### 5.3 Return to Welcome

When `time_kiosk_return_seconds` is above 0, every screen other than Welcome (the profile, "not found") returns to Welcome after that many seconds.

- **Where it hooks in.** One line in `_kiosk.html.erb`, `<%= render "time_kiosk/return_timer" unless @time_kiosk.tool == "welcome" %>`, renders a new partial. It goes after the right column's closing `</div>` (line 33), so line 33 separates it from Phase 1's edit to line 32. The partial attaches a new Stimulus controller, `kiosk_return_controller.js`, with the seconds as a value.
- **Countdown.** It restarts on any tap or key press inside `#kiosk-content`. A small "Returning in 12s" note shows in the corner so people know why the screen will change.
- **The Manager window.** While a modal inside `#kiosk-content` has `.show`, the countdown pauses for at most `max(return_seconds, 60)` seconds without input. After that it closes the modal and returns anyway, so Time Management can't be left open on a shared screen. Phase 1's references expire after 5 minutes regardless.
- **Returning.** It returns with `Turbo.visit("/time_kiosk")`, a normal visit that renders Welcome. A plain `fetch` would get HTML, not a stream, and wouldn't be swapped in.
- **Cleanup.** `disconnect()` clears the timer. The next scan replaces `#kiosk-content`, which disconnects it, so timers never stack.

### 5.4 Kiosk users

When `time_kiosk_users_team` is set, a `before_action` lets through only admins and **direct** members of that team (`current_user.person&.teams&.exists?(id: team_id)`). It doesn't use `person.all_teams`, because that includes managers of parent teams and members of child teams. Everyone else goes to the dashboard with "The time kiosk is for kiosk accounts only."

This is the stopgap until Phase 4. Setup: a top-level "Kiosk" team whose only member is the kiosk account from step 0.

### 5.5 Upstream files touched

- `lib/settings.rb`: three lines after `time_clock_max_hours`
- `app/controllers/time_kiosk_controller.rb`: the `AutoClockIn` call in `find_token`, and the `before_action` line
- `app/views/time_kiosk/_kiosk.html.erb`: one render line after line 33, separated from Phase 1's edit to line 32

New files:
- the two inputs
- `TimeKiosk::Config` and `TimeKiosk::AutoClockIn`
- the timer partial and Stimulus controller
- `test/models/time_kiosk/auto_clock_in_test.rb`, `test/controllers/time_kiosk_auto_clock_in_test.rb`, and `test/inputs/` tests (none go in Phase 1's test file)

### 5.6 Tests

- `AutoClockIn`: every row of the table in 5.2, including clocked out earlier today, a missed clock-out from yesterday, a period whose last day is today (not current, as on the profile), and a deleted period.
- Controller:
  - A scan with the setting on creates one punch and shows the banner. A second scan creates nothing more. A scan after clocking out creates nothing. A scan with yesterday's punch still open creates nothing and shows the warning.
  - With the setting off, the kiosk behaves as today.
  - A value saved in the PStore by "another process" (written straight to the store) applies to the next scan without a restart.
  - Kiosk users: direct members and admins get in. A member of a child team, a manager of a parent team, and an unrelated user are turned away. A blank setting lets everyone in.
- Inputs: the stored value renders as selected, "Off" is selected when the value is blank, there is exactly one blank option, and an ended but stored period still appears.
- By hand on Ditto with a USB scanner:
  - Focus is back in the token box after the auto clock-in screen. The fact check expects this: Turbo 8 refocuses the stream's `[autofocus]` element when focus fell to `<body>`, and also restores focus to the same id.
  - The timer returns to Welcome, restarts on a tap, pauses while the Manager window is open, and gives up after the cap.

## 6. Phase 3a: Widgets on the kiosk profile (`feature/widgets`)

### 6.1 Placement

Add `kiosk` to `Widget::PLACEMENTS`, labelled "Time kiosk, after a scan". It touches one upstream file. `_found_person.html.erb` gets one line after the last row of the card body:

```erb
<%= render "widgets/kiosk_slot", person: @person %>
```

Only `person` is passed. The Reminders widget needs nothing else, and passing Phase 2's period or punch would make `feature/widgets` depend on another branch's instance variables. Add more locals later, with a declared dependency, if a widget needs them.

The slot renders nothing when the widgets feature is off. Phase 1 edits the button URLs in this file, and this line comes after them. Recheck with a trial merge once Phase 1 is built.

### 6.2 Who sees which widget

The slot does not use `policy_scope`, which is scoped to `current_user`, the kiosk account. It queries:

```ruby
Widget.enabled.where(placement: "kiosk").in_order.select { _1.visible_to_person?(person) }
```

`Widget#visible_to_person?(person)` checks, in this order:
1. `false` unless the widget is `enabled`.
2. `true` if `person.user&.admin`.
3. The viewer level against the **scanned person's** teams: `user` → true, `team` → `person.all_teams.include?(team)`, `manager` → `team.manager?(person)`, `admin` → false.

A person with no login passes `user`-level widgets and the team checks. Because of step 2, an admin's scan shows every enabled kiosk widget, as admins see every widget on the dashboard. The widget's own ERB can still hide itself from admins.

### 6.3 Rendered inline, not in a Turbo Frame

On the dashboard each widget body loads from `GET /widgets/:id/body`. The kiosk can't do that: the body would need the person in its URL, and any signed-in user could then read anyone's reminders by changing the id. Kiosk widget bodies render inside the kiosk's own response, so seeing them requires the person's card, which is already what it takes to see their profile.

The dashboard card can't be reused as-is. `_card.html.erb` starts `hidden`, and `widget_card_controller.js` unhides it only on `turbo:frame-load`. The changes:
- Move the inner body markup of `widgets/body.html.erb` into a shared partial, `widgets/_body_content` (`widget:`, `html:`). `body.html.erb` keeps its frame around that partial.
- Add a new `widgets/_kiosk_card`: no `hidden`, no `widget-card` controller, no frame. It renders `_body_content` and is printed only when `widget_blank?` is false. The blank check happens on the server.
- `widget_controller.js` (styles, shadow root, JavaScript with cleanup) works unchanged. Its `refresh` uses `closest("turbo-frame")?.`, which is safe without a frame, and the kiosk layout loads the same Stimulus controllers.
- `refresh_seconds` is ignored for kiosk widgets, and the form hides the field when the placement is `kiosk`.

### 6.4 Rendering and errors

The helper's signature becomes `render_widget_content(widget, details: current_user&.admin, person: nil)`.
- Keyword arguments are locals in the method's `binding`, so `ERB.new(...).result(binding)` sees `person`.
- Dashboard calls are unchanged: `person` is nil, and `details` behaves as today.
- `widget_error(error, details:)` shows the error message only when `details` is true. The kiosk slot passes `details: false`, so no message appears on the shared screen even while the kiosk is signed in as an admin.

The widget form says: "On the kiosk, use `person` (whoever scanned). `current_user` is the kiosk's own account." Kiosk ERB should query only `person`'s own records. Only architects can write ERB, as before.

### 6.5 Kiosk widgets elsewhere

- **Dashboard.** `_slot.html.erb` already filters by placement, so kiosk widgets never appear there, and dashboard widgets never appear on the kiosk.
- **`WidgetPolicy#body?`** is false for `placement == "kiosk"`. The body URL would render with no `person`, and a Reminders widget visible to everyone would otherwise be fetchable by every student.
- **The show page's preview** of a kiosk widget renders inline as the viewer's own person (`person: current_user.person`), labelled "Preview: how this looks at the kiosk for you". It doesn't use the body URL. A viewer with no Person sees "No profile to preview as" instead.
- **Copy that says "dashboard"** gets "dashboard or kiosk" where it applies: the form intro, "Where on the dashboard", the index intro and the show page.

### 6.6 Hiding

As on the dashboard, a widget whose ERB renders only whitespace isn't shown. A person with nothing to be reminded of sees no card.

### 6.7 Files

- Upstream file newly touched by `feature/widgets`: `app/views/time_kiosk/_found_person.html.erb` (one line). Add it to the widgets row in `FORK.md`.
- Everything else is widget files: model, policy, helper, form, index, show, `body.html.erb`, the new `_body_content`, `_kiosk_slot` and `_kiosk_card`, and tests.

### 6.8 Tests

- A kiosk widget renders on the profile with the right `person` and isn't on the dashboard. A dashboard widget isn't on the kiosk.
- `visible_to_person?`:
  - A disabled widget is hidden even for an admin.
  - The team and manager levels are checked against the scanned person.
  - A person with no login sees only `user` and team-member widgets.
- ERB that renders blank prints no card.
- An ERB error shows the fallback with no message, even when the kiosk account is an admin.
- `body` refuses a kiosk widget.
- The preview renders as the viewer.
- With the feature off, the slot renders nothing.

### 6.9 Widgets spec

Update `docs/widgets-spec.md` on `feature/widgets`: §1.1 no longer says "dashboard only", §4 gets a kiosk subsection pointing here, and §5 gets the `body?` rule.

## 7. Phase 3b: The Reminders widget (content)

The source is `~/dev/gatherpack/pages/kiosk-reminders-widget.rb`, a find-or-update-by-title script like the Kickoff Countdown. The widget is:
- placement `kiosk`, viewer "Everyone signed in", dynamic, title "Reminders"
- ERB that lists only `person`'s open items and renders nothing when there are none

Settings at the top of the source, as in the report pages: the roster teams, the season, badge names, and which reminders are on.

**Who gets reminders.** The ERB returns nothing unless `person` is a regular (non-manager) member of the roster teams or their sub-teams. This is the same rule as the Eligibility Report (`eligibility-report.html.erb:7-9, 71`). `person.all_teams` would also include mentors who manage the team. Mentors see nothing.

**First set:**

| Reminder | Check | Message |
|---|---|---|
| FIRST | Neither "*{season+1}* FIRST Registered" nor "… Consent Signed" badge | "You're not on the FIRST team roster yet." |
| | Registered but not Consent Signed | "FIRST consent form not signed yet." |
| Safety training | No "*{season+1}* Season Safety Training Complete" badge | "Safety training not done yet." |
| Not registered | `person.user` missing or without an email | "You don't have a GatherPack login yet. Ask a mentor." |
| Forms to complete | `forms_to_complete(person)` (`feature-forms/app/helpers/forms_helper.rb:118`), the same list as the dashboard card | "Forms to fill in: *Meal Choices*, …" |

Rules carried over from the reports:
- **A missing badge.** If a season badge doesn't exist yet, skip that reminder. Otherwise every student would be told they haven't done it. The reports do the same and warn admins.
- **Forms are guarded** with `GatherPack::Features.enabled?(:forms) && respond_to?(:forms_to_complete)`. `forms_to_complete` doesn't touch `current_user`, so it is safe at the kiosk. It also lists the person's **wards'** forms, which matters if a parent scans. Students have no wards, so for students the list is their own.
- **FIRST is informational** in the Eligibility Report (`first_required = nil`). The kiosk shows it anyway, as a reminder. The setting at the top of the source can turn it off.

Later, if wanted: attendance below the month's target, and concession shifts short. That logic lives in the 454-line Eligibility Report page. Copying it would drift, so first move the calculations somewhere both can use (to be decided when it comes up).

Privacy: the kiosk is a shared screen. Corey accepted this on 2026-10-09. Change the widget if it becomes a concern.

## 8. Phase 4: Kiosk devices (on hold)

Start only when Corey asks. It is recorded here so the earlier phases don't box it in.

**Idea.** A kiosk is a device, not a person. Today it borrows a person's login, so it can do everything that person can, and anyone with a login can turn a browser into a kiosk.

**Pairing.** On the device, an admin opens Setup → Kiosks → **"Make this browser a kiosk"** and names it ("Shop"). GatherPack:
1. Creates a `Kiosk` record.
2. Sets a long-lived, signed, http-only device cookie holding a random secret. Only a digest is stored.
3. Signs the admin out.

From then on the browser opens only the kiosk. It has no user session, so there's no dashboard behind the logo and nothing to expire. Revoking it from the Kiosks list ends it at once.

**Access.** Kiosk routes accept a paired device, or an admin for testing. This replaces `time_kiosk_users_team` and step 0. The kiosk layout needs a header with no user and no link to `/`.

**Per-kiosk settings.** The auto clock-in period and the return seconds move from global settings onto `Kiosk`, so the shop kiosk and an outreach-event laptop can lock to different periods. The first kiosk paired copies the current global values, and the global settings are then removed. Reading per request from the record also ends the per-process settings problem for these keys.

**Manager actions** keep Phase 1's signed reference. Rate limiting becomes per device.

**Audit.** The audit log's `whodunnit` is a `uuid` column (`db/versions_schema.rb`). Anything that isn't a UUID is silently stored as NULL, and the audit log shows only User names. Recording which kiosk made a punch needs either PaperTrail metadata (a migration on the versions database) or a `kiosk_id` column on punches. Decide when the phase starts.

**Hooks.** `Kiosk` includes `CanBeHooked`. Add `kiosks - create/update/destroy`, plus domain events `kiosk - clock in` and `kiosk - clock out`. Their record is the punch, and the hook can read the kiosk.

**Data model sketch.** `kiosks`: `name`, `secret_digest`, `time_clock_period_id` (optional), `return_seconds` (default 0), `last_seen_at`, `enabled`, timestamps. Neat id prefix `ksk`.

**Cost.** This changes upstream's kiosk itself: the access check, the layout header, and possibly `routes.rb`. It is a general design, not an HBR one. Whether to offer it upstream is Corey's call when the phase starts.

## 9. Hooks

- **Phase 1:** none. It changes who the kiosk acts for, not what it records.
- **Phase 2:**
  - An auto clock-in creates the punch through the model, so `TimeClockPunch`'s `CanBeHooked` callbacks fire, as for any punch.
  - `Hook.catalog` doesn't list `time_clock_punches`, `time_clock_periods`, budgets, gateways, mailboxes or several others that include `CanBeHooked`, so their events can't be chosen in the Hooks form. That's upstream catalog drift, tracked as BL-014.
  - No new domain event. Without a device identity, a "kiosk - clock in" event would only duplicate the punch's create. It comes with Phase 4.
- **Phase 3:** none. Rendering is read-only (widgets spec §9).
- **Phase 4:** see §8.
- **`token - activate`** is listed in the catalog but never fired. Running a hook from a scanned card is unfinished upstream, and Phase 1 shows "not found" for those tokens instead of a 500. Finishing it is not in scope.

## 10. Upstream bugs found while writing this

| Bug | Handled by |
|---|---|
| Kiosk trusts browser ids, mutates over GET, renders `tool` from the browser, has no lookup limit; a Hook's token is a 500; `punch_out` re-closes closed punches | Phase 1 |
| Punches with no period crash the profile; "Start Unassigned" does nothing | BL-012 (updated with the second point). BL-012 and Phase 1 both touch `_found_person.html.erb:81` and the kiosk tests, so BL-012's tests go in a new file. If BL-012 removes the button, whichever lands second drops Phase 1's URL change for it. |
| Settings values are cached per process, so a save reaches only one Puma worker until a restart | BL-013 (Phase 2 reads its keys fresh as a workaround) |
| `Hook.catalog` misses models that include `CanBeHooked` | BL-014 |
| The kiosk ignores `Token.rfidify` for `5700…` reads | Noted only (§4.4) |
| The kiosk layout raises for a user with no Person | Noted only. Step 0's account has a Person. |

## 11. Decisions (2026-10-09)

1. A second scan while clocked in shows the profile with Clock Out. It never clocks out.
2. Mentors scan like everyone else: clocked in if they're on the period's team and have no punch in it today, and they see the Manager button.
3. Reminders on a shared screen are acceptable. Change the widget if that becomes a concern.
4. Return to Welcome is configurable, default off.
5. Kiosk widget bodies render inline for the scanned person, never through a URL that takes a person id.
6. Kiosk devices are a separate, later phase (Phase 4), started only when Corey asks.
7. (Rev. 2) A scan after clocking out earlier the same day does not clock the person back in. They press Clock In if they're back. This stops a scan to check hours, or a mentor's end-of-night scan, from creating a new punch.

## 12. Open questions

1. Is Phase 2 meant for upstream? It's written to upstream standards either way, and this changes only the timing of any issue, which Corey raises.
2. Should the kiosk nag about FIRST registration while the Eligibility Report treats it as informational (§7)? The default here is yes.
