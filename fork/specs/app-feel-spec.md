# Spec: App feel

Status: rev. 3, 2026-11-08. Being built. Pitch: [`09-app-feel.md`](../pitches/09-app-feel.md). Code facts checked against integration `45405a02` and `turbo-rails` 2.0.23. Decisions are in §11.

Rev. 3: Phase 0 no longer blocks the build; the opt-out count is redone at build time; sidebar additions use the slots seam.

Rev. 2: automatic reminders for forms coming due and for what people still owe are in scope (§8.8, decision 10).

Independent of [`modern-skin-spec.md`](modern-skin-spec.md) and [`my-gatherpack-spec.md`](my-gatherpack-spec.md), and could ship first.

## 1. Goal

Make GatherPack feel like an app, on the Hotwire stack it already has: no jarring page changes, saves that keep your place, an icon on the home screen, and reminders that reach a phone. Rewriting screens and offline use are out of scope.

| Goal | Measure |
|---|---|
| The flicker people report is gone | The Phase 0 recordings, repeated: each item listed is fixed or explained |
| Clicking a name in a list doesn't reload the whole page | No full document load on any link in §5.1's table |
| Saving on a page and returning keeps your place | Scroll position is unchanged after each action in §5.2's table |
| Installs cleanly | Chrome's installability checks pass; opens full screen with the right name and icon on Android and iPhone |
| Phone reminders arrive | A real Android phone and a real installed iPhone receive one for each topic in §8.5 |
| A bad service worker can be removed | Turning the flag off removes it from a device, tested before shipping |

## 2. What the code shows

- **Turbo 8 is present but its refresh features are unused.** `turbo-rails` 2.0.23 includes morphing and scroll preservation, and no layout sets them.
- **Turbo opt-outs.** 49 in 34 upstream view files when this was written; fork features have added more, 85 on integration `45405a02`. Most are the same pattern, `"data-turbo": "false"` on a link in a list row (`_person`, `_hook`, `_token` and others). **This may be the main cause.**
  - Index pages render rows inside `turbo_frame_tag "results"`. A plain link in a frame would load inside the frame and show "Content missing".
  - Opt-outs were added to stop that (commit `8e730ad3`, "fixed content missing"). The result is a full page reload each time someone clicks a name in a list.
  - `data-turbo-frame="_top"` is the intended fix: it leaves the frame and keeps Turbo.
- **The other 19:** sign-in and external login (6), Doorkeeper consent (3), calendar containers (5), the badge card header, a team's member link, Stop Impersonating, the kiosk link, and the ledger payment form.
- **Morph only applies to a redirect back to the exact same URL.** Turbo's `getDefaultAction` uses `replace` only for that case, and `isPageRefresh` requires it. Saves that go from an edit page to a show page are normal visits, and correctly scroll to the top. Actions that stay on a page are the ones that gain, such as the sign-up roster and event check-ins.
- **Icons are JavaScript-rendered.** `font_awesome_tag` loads Font Awesome's SVG+JS build from a CDN, which swaps each `<i>` for an `<svg>` on the page. The server sends `<i>` and the page holds `<svg>`, so a morph sees a difference on every icon (§5.3). The icon picker in `font_awesome.js` relies on this build and queries the Font Awesome API for names, so the CSS font build isn't a drop-in swap.
- **The calendar is JavaScript-built.** `calendar_controller.js` builds FullCalendar in `connect()` into an empty `#calendar`. A morph would empty it, and `connect()` wouldn't run again.
- **Sidebar contents vary.** It holds impersonation state, and later could hold counts. On phones it's a Bootstrap off-canvas panel.
- **PWA pieces.** `pwa/manifest.json.erb` has a blank `short_name`. `pwa/service-worker.js` is all comments, and nothing registers it. The application, devise and kiosk layouts link the manifest.
- **Reminders are mostly manual.** `FormScheduleJob` only opens and closes forms. Form reminders go out when a leader presses Send (`FormReminderSender`). `SignupReminderJob` is automatic. `AnnouncementNotificationRouter` runs when `notify_now` is set. `CommitmentsController` line 89 is a manual email. Each calls `SendEmailJob` directly, so there's no shared delivery layer.
- **Gateways fit the push keys.** `Gateway` is STI with `store_accessor :configuration`, a registry per service, and a `finish_setup` step, and it's already managed from a page. Admins set up email this way.

## 3. Phase 0: reproduce it

The glitch hasn't been reproduced yet. Timed desktop page visits took about 190–380 ms with almost no layout shift, except the dashboard (a 0.07 shift and a second draw). Saving forms and phones weren't tested.

Record real use on a real phone and a desktop, against the staging copy: clicking through lists, saving forms, the dashboard, the calendar, time clock. List exactly what flickers, in the words of the person who noticed it. This list is the acceptance test for §5, and it sets the order. Time the list links before and after §5.1.

**This doesn't block the build.** Frame links are a bug fix regardless. The recordings happen on the staging copy once frame links are there, and they decide which pages join the morph list (§5.2).

## 4. Branches and flags

| Branch | Based on | Contents | Flag | Upstream |
|---|---|---|---|---|
| `feature/turbo-frame-links` | `upstream/main` | §5.1 | None; a bug fix | Strong candidate |
| `feature/smooth-pages` | `upstream/main` + `feature/sidebar-slots` | §5.2–5.5 | `feature_smooth_pages`, off | Candidate |
| `feature/local-assets` | `upstream/main` | §6 | None; pages look the same | Candidate |
| `feature/installable-app` | `upstream/main` + `feature/sidebar-slots` | §7 | `feature_installable_app`, off | Candidate |
| `feature/phone-notifications` | `feature/installable-app` | §8 core, announcements | `feature_phone_notifications`, off | Candidate |
| `feature/phone-notifications-forms` | core + `feature/forms` | Form reminders | Same flag | With forms |
| `feature/phone-notifications-signups` | core + `feature/signups` | Shift reminders | Same flag | With sign-ups |
| `feature/phone-notifications-commitments` | core + `feature/commitments` | Commitment emails | Same flag | With commitments |
| `feature/forms-auto-reminders` | `feature/forms` | Reminder before a form's deadline (§8.8) | `feature_forms_auto_reminders`, off | With forms |
| `feature/commitment-monthly-reminders` | `feature/commitments` | Monthly reminder of what's owed (§8.8) | `feature_commitment_monthly_reminders`, off | With commitments |

Each ships separately. **`feature/turbo-frame-links` goes first:** it's the smallest change and it may be the largest improvement.

**Upstream files edited**

| File | Branch | Change |
|---|---|---|
| 30 list partials and index pages | turbo-frame-links | `"data-turbo": "false"` becomes `data: { turbo_frame: "_top" }` |
| `app/views/layouts/application.html.erb` | smooth-pages, installable-app | One line each, for a partial in the head |
| `app/views/welcome/dashboard.html.erb`, calendar pages | smooth-pages | No-preview, calendar permanence, placeholders |
| `app/views/layouts/{application,devise,kiosk}.html.erb` | local-assets | Font and Popper lines |
| `app/helpers/font_awesome_helper.rb`, `config/importmap.rb` | local-assets | Local Font Awesome |
| `app/views/pwa/manifest.json.erb` | installable-app | Short name, `id` |
| `app/views/pwa/service-worker.js` | installable-app | Renamed to `.js.erb`, real content |
| `Gemfile`, `Gemfile.lock` | phone-notifications | `web-push` |
| `config/routes.rb` | phone-notifications | Subscription and settings routes |
| `config/recurring.yml` | the two reminder branches | One job each |

## 5. Smooth pages

### 5.1 Frame links (`feature/turbo-frame-links`)

Replace the list-link opt-outs with `data: { turbo_frame: "_top" }`, in batches by area, checking each destination. Report "Run" is one of the 30 but is reviewed separately (table below). The files include `_person`, `_event`, `_event_type`, `_team`, `_team_type`, `_badge_type`, `_hook`, `_report`, `_token`, `_variable`, `_audit_log`, `_announcement`, `_question`, `_checkin`, `_membership`, `teams/show`, and the `questions` and `announcements` index pages. The team card's member link (`data: { turbo: false }`) is treated the same.

The change also applies to links not in a frame, where `_top` is harmless. Destinations that rely on a full load (a page script bound to `DOMContentLoaded`) are found by clicking through each in a system test; `turbo:load` handlers and Stimulus are unaffected.

The rest are reviewed one at a time:

| Opt-out | Result |
|---|---|
| Sign-in form, external login buttons (6), Doorkeeper consent (3) | **Keep.** Redirects leave the site, or the layout changes |
| Stop Impersonating | **Keep.** The whole sidebar must change |
| Time Clock Kiosk link | **Keep.** The layout changes completely |
| Ledger payment form | Keep unless the payment flow is shown to work without it, tested with the gateway's test mode |
| Calendar containers (5) | Clicking an event loads fully. Remove only with the calendar check in §5.3 |
| Badge card header | Treat as a list link |
| "Run" on a report | Keep if the report's output needs a full load; check |

### 5.2 Morph and scroll (`feature/smooth-pages`)

A head partial, `layouts/_smooth_pages_head`, adds the two meta tags only when the flag is on and the page has opted in:

```erb
<%= tag.meta name: "turbo-refresh-method", content: "morph" %>
<%= tag.meta name: "turbo-refresh-scroll", content: "preserve" %>
```

**Opt-in by page, not global.** A page opts in with `content_for(:smooth_refresh, true)`, or a controller list in the initializer. A global switch would change pages nobody has tested, including forms with unsaved input. First set, each with a test:

| Page | Actions that come back to it |
|---|---|
| Sign-up roster (`roster_signup_sheet_path`) | Place, mark, move, remove. Redirects with a query string (`event_id`) only count when the current URL has the same one |
| Sign-up sheet | Sign up, change, cancel |
| Event page | Check in, check out (`redirect_to @event`) |
| Time Clock Kiosk management, Team and Badge member lists | To be confirmed by the same check |

Saves that move to another page (edit to show) stay as they are.

### 5.3 What morph and permanence can break

| Risk | Handling |
|---|---|
| Icons: server `<i>` versus page `<svg>` on every morph, which would remove and redraw every icon | On `turbo:before-render`, only when the render is a morph, pause it, run `FontAwesome.dom.i2svg` on the incoming body, then resume, so the morph compares `<svg>` to `<svg>`. Always resume, even if Font Awesome is missing or fails. A `turbo:before-morph-element` listener can't do this: Turbo never pairs elements with different tags. If this fails on a page, that page stays out of the opt-in list |
| Calendar emptied by a morph | Put `data-turbo-permanent` on `#calendar` on pages that opt in. Otherwise leave them out of morph |
| Stale permanent sidebar | See below |
| Off-canvas left open on phones, with its backdrop gone | Close the off-canvas on `turbo:before-visit` |
| Bootstrap menus, modals, tabs open during a morph | Check each page in the first set. Modal-based forms already close on `turbo:submit-end` |
| Unsaved text in another form on the same page | Check per page. Morph can overwrite it, so such pages stay out of the opt-in list |
| Trix, CodeMirror, `modal_form`, `tick_list`, `widget_card` | Check on any page in the set. Leave those pages out if needed |

**Sidebar.** `data-turbo-permanent` keeps the sidebar still between pages. But a permanent element keeps old content, which would be wrong after impersonating, a permission change or a new count. So its `id` carries a digest of what it renders:

```erb
<% nav_id = "sidebar-#{Digest::SHA256.hexdigest([ current_user.id, true_user.id, admin?, nav_fingerprint ].join("/"))[0, 12]}" %>
```

The `id` and `data-turbo-permanent` are registered as root attributes in the sidebar slots seam (`feature/sidebar-slots`), so they apply to the original sidebar and to My GatherPack's replacement alike. Turbo keeps the element only when the new page has the same `id`. If the contents would differ, the digest differs and the sidebar is replaced normally. `nav_fingerprint` is the labels of the visible items.

A small Stimulus controller updates the `active` class after each visit, using the same rules as `active_status` in `nav_helper.rb`. The special cases there (`/events` highlights Calendar) are sent to the browser as data, so they aren't written twice. It also keeps the sidebar's scroll position, the most visible gain.

### 5.4 Dashboard

- **No double draw.** Add `turbo_exempts_page_from_preview` on the dashboard, calendar and time clock pages. A return visit waits for fresh content, about 200–400 ms, and doesn't show old content first.
- **Placeholders.** Widget cards and calendars that fill in later get a `min-height` matching their usual size, with Bootstrap's `placeholder-glow`. This removes the 0.07 shift.

### 5.5 Page transitions

Turbo's view transition support (`<meta name="view-transition" content="same-origin">`) is a one-line trial. Try it last, on the same flag, on a phone. Keep it only if it's clearly better, and honor `prefers-reduced-motion`.

## 6. Local assets (`feature/local-assets`)

The first load is about 70 files and 4.3 MB uncompressed. Today's CDN files mean a cold cache depends on outside services.

- Font Awesome: vendor the same SVG+JS version (7.0.0) and load it from GatherPack. The full free set stays, since admins pick icons by name. Keep `mutateApproach: "sync"`.
- Fonts: vendor Fira Sans, Fira Code and Bubblegum Sans as `woff2` with `font-display: swap`, and remove the Google Fonts lines from three layouts. Use a subset (weights the CSS uses), and don't carry the full italic range unless the audit finds it's used.
- Popper: vendor the same version. Check whether the Bootstrap import already provides it, and remove the duplicate if so.
- The icon picker's Font Awesome API call stays, as it's admin-only. Note in the code that this one call is still external. A local icon list is a possible follow-up.
- Propshaft already gives these files digested names. Confirm the production proxy sends far-future cache headers and compression for them. If it doesn't, that's the larger gain.

Measure before and after on a throttled connection: bytes, requests and first paint for a cold and a repeat visit. With no visible change, this needs no flag, but check the three fonts render as today.

## 7. Installable app (`feature/installable-app`)

### 7.1 Manifest

- New setting `pwa_short_name` ("Name on the home screen", 12 characters or fewer, falling back to `Settings[:title]`).
- Add `id: "/"`. Keep `display: standalone`.
- Description comes from settings. "Get together with GatherPack" stays as the default.
- Icons: existing `pwa_icon` variants, and also `"purpose": "any maskable"` when the admin's icon suits it.

### 7.2 Service worker

`app/views/pwa/service-worker.js.erb`, served by the existing `rails/pwa#service_worker` route with `Cache-Control: no-cache`.

**When the flag is on:**

```js
const VERSION = "<%= service_worker_version %>"
const ASSETS = `assets-${VERSION}`
```

`service_worker_version` is a digest of the app's asset manifest. `gatherpack_revision` can't be used because it's blank unless `GATHERPACK_REVISION` is set.

- `install`: cache `/offline.html`.
- `activate`: delete old caches.
- `fetch`:
  - `GET` under `/assets/`: cache first. Names are digested, so a cached copy can't go stale.
  - Page navigations: network only. On a network failure, show `/offline.html`.
  - **Everything else: not handled.** Signed-in pages, Turbo Frame requests, JSON and Active Storage files are never stored.

The offline page is static (`public/offline.html`), with no layout and no user data: "You're offline. Check your connection and try again," and a Try again button.

A test reads the served script and fails if the caching branch matches anything outside `/assets/` and `/offline.html`.

**When the flag is off:** the same URL serves a script that deletes its caches and unregisters itself. Browsers check for a new service worker on navigation, so devices clean themselves up. The registration script (rendered only when the flag is on) can't do this alone, because a page with the flag off doesn't load it.

Registration is in the application layout's head partial, on `load`, so it doesn't compete with first paint. The kiosk layout doesn't register. The worker's scope still covers the kiosk if the same browser installed it, but all it does is serve digested assets and the offline page.

### 7.3 Standalone mode

Opening full screen removes the browser's Back button and address bar, and on iPhone there's no pull to refresh. Check that every flow has a way back. Breadcrumbs provide this on desktop widths, and [`my-gatherpack-spec.md`](my-gatherpack-spec.md) hides them on phones in favor of the tab bar, so add a Back button in the header for `display-mode: standalone` if testing shows a dead end. External links (`target="_blank"`) must open outside the app.

### 7.4 Install help

A small "Add to Home Screen" entry in the sidebar (a sidebar slot), shown only in a browser (not already installed) on a phone. On Android, it calls the saved `beforeinstallprompt`. On iPhone, it shows the steps: "In Safari, tap Share, then Add to Home Screen." There's no popup or banner on page load.

## 8. Phone notifications (`feature/phone-notifications`)

### 8.1 Setup for admins

`Gateway::WebPushGateway`, registered as `Gateway.register(self, :push_sending)`. Setting it up takes one click. `finish_setup` generates the VAPID key pair and stores it in `configuration`. The only field is a contact address, which push services require.

No server configuration or restart is needed, and it works the way email gateways do. Replacing keys invalidates every subscription, so the page warns about that, just above Save.

### 8.2 Data

One reversible migration:

```
push_subscriptions
  id           uuid
  user_id      uuid, not null, FK, index
  endpoint     text, not null, unique
  p256dh       string, not null
  auth         string, not null
  device_label string              # "Chrome on Android", from the user agent
  last_sent_at datetime
  timestamps

push_preferences
  id              uuid
  user_id         uuid, not null, FK, unique
  enabled_topics  string[], not null, default []
  timestamps
```

No `has_paper_trail` on either. The endpoint and keys shouldn't be copied into the audit log, and these rows aren't records of anything people did to each other. `p256dh` and `auth` are encrypted with Active Record encryption if it's configured in the app; check at build time.

### 8.3 Delivery

```ruby
GatherPack::PushChannel.deliver(person, topic: :shifts, title: "Your shift is Saturday at 9:00 AM", path: signup_sheet_path(sheet))
```

- Does nothing if the flag is off, no gateway exists, the person has no login, or the topic isn't enabled for them.
- Sends one `SendPushJob` per subscription, the same pattern as `SendEmailJob`.
- `WebPush.payload_send` with the gateway's keys. A gone or invalid subscription (404/410) deletes the row. Network and 5xx errors retry a limited number of times. Check the gem's exception names at build time.
- **Payload: title and path only.** No body text with personal details, and no other person's name. A person's lock screen may be in view of others.
- `path` is checked to be a local path. The service worker's `notificationclick` opens it, focusing an existing window if there is one.

It's an addition to email, never a replacement. Failures here can't affect email, since they run in separate jobs.

### 8.4 Topics

```ruby
GatherPack::PushTopics.register(:shifts, label: "My shifts", hint: "The day before, and any changes", default_on: true)
```

Connector branches register their own, and the settings page lists whatever's registered and enabled.

### 8.5 What sends in the first version

These attach to sends that exist today. §8.8 adds the two automatic ones.

| Topic | Label | Source | When | Branch |
|---|---|---|---|---|
| `forms` | Forms | `FormReminderSender` | A leader presses Send | forms connector |
| `shifts` | My shifts | `SignupNotices` reminder and change notices | `SignupReminderJob`, or a change | signups connector |
| `announcements` | Announcements | `AnnouncementNotificationRouter` | `notify_now` is set | core |
| `commitments` | What I still owe | `CommitmentsController` email | An organizer sends it | commitments connector |

Connectors `prepend` a small module on the service, with no edits to upstream or feature code beyond that. The announcement router sends to everyone on a team; since it may be many people, the jobs are queued as today's emails are.

The mockup's settings page says "A few days before the deadline" and "A reminder once a month". Those hints describe §8.8, and a hint appears only once its reminder branch is on. Until then, the labels match the table above.

### 8.6 Settings page

`GET /notifications`, signed-in people, reached from the sidebar.

- Top card: "Notify me on this phone", with "Email reminders keep coming either way." A toggle per device.
- Second card, "Tell me about": one toggle per topic, with its hint, for the person.
- iPhone not installed: "On an iPhone? Add the app to your Home Screen first. In Safari, tap Share, then Add to Home Screen." The first toggle stays off until then.
- Permission blocked: "Notifications are blocked for this site. You can turn them on in your browser's settings."
- A short list of the person's other devices with a Remove button.

The browser's permission prompt appears only when someone turns on the first toggle. Never on page load. iPhone requires that gesture anyway.

### 8.7 Device and account safety

| Case | Rule |
|---|---|
| Sign-out | Delete this device's subscription. The session holds its id, set on subscribe and on the sync below. A Warden `before_logout` hook does the delete, so it works however sign-out happens |
| Next person signs in on that browser | The browser still holds a subscription. `POST /push_subscription/sync` runs on load and sends the endpoint. It updates a row only if the row already belongs to this user. **It never creates a row or moves one to a different user**; if the endpoint is unknown, the browser unsubscribes. Only the explicit toggle attaches a device |
| Explicit opt-in on a device held by another user | The row moves to the person who opted in |
| Impersonating | Subscribe and settings are refused. Otherwise an admin's phone would receive someone's reminders |
| Kiosk | Never prompts. The controller doesn't load in the kiosk layout |
| A login is removed, or a person's access changes | `dependent: :destroy` on user. Payloads don't carry permissions; the link opens a page that checks them |
| Flag off | Nothing sends. Subscriptions stay until the worker's cleanup on each device, so a brief off doesn't lose people's opt-ins. Note that §7.2's unregistering also ends push on that device until they return |

Controllers inherit `InternalController` and authorize against `current_user`'s own rows, in a new `PushSubscriptionPolicy`.

### 8.8 Automatic reminders

Neither of these exists today, by email or otherwise. They send **email first**, and a phone notification too for anyone who has opted in. They work without phone notifications, so they can ship before them. Each is off until a leader turns it on for a specific form or commitment, so turning on the flag sends nothing by itself.

**Forms coming due** (`feature/forms-auto-reminders`)

- One reversible migration on `forms`: `auto_reminder_days` (integer, not null, default 0, meaning none, the same convention as a sign-up sheet's `reminder_days`) and `auto_reminded_at` (datetime).
- On the form's edit page, near the deadline: "Remind people who haven't answered [3] days before the deadline." New forms start at 3 and existing forms at 0, so an open form never starts sending because of a deploy. It's hidden when the form has no deadline.
- Once set, the form page says who and when: "An automatic reminder goes out November 9 to people who haven't answered."
- `FormAutoReminderJob`, hourly in `config/recurring.yml`, finds open forms inside their window with `auto_reminded_at` null and a deadline still ahead. It stamps `auto_reminded_at` under a row lock before sending, so a retry can't send twice. It does nothing while forms or the flag are off.
- It sends through `FormReminderSender`, so wording, guardian rules and the `FormReminder` record match a manual send. `sent_by` is null, which the column allows, and the form's reminder history shows it as "Automatic". Guardian nudging follows the manual default (off on a form's first reminder, on after that). Guardians who must act are always included.
- **Who still owes:** the manual path gets this from `FormReport`, which is built for one viewer. The job has no viewer, so the "not complete" list is extracted into something both can call, with a test that the two agree.
- Moving the deadline later clears `auto_reminded_at`, so the new date gets its own reminder. Manual reminders don't affect it. Whoever sends one by hand a day earlier may want to set this to 0.

**What people still owe** (`feature/commitment-monthly-reminders`)

- One reversible migration on `commitments`: `monthly_reminder` (boolean, default false) and `monthly_reminded_on` (date).
- On the commitment's edit page: "Remind people who still owe, once a month."
- `CommitmentMonthlyReminderJob` runs at 9:00 AM on the 1st of each month. It covers running commitments with the box ticked and not yet stamped for this month, and stamps each one as it goes.
- It sends **one email per person, however many commitments they owe**, listing each with what's left (`commitment_summary`) and a link to their commitments page. People who've met everything get nothing. Recipients are the same as the organizer's manual message (the open progress's `members`, with a login), so grouped commitments reach each member of the family.
- Phone topic: `commitments`, one notification per person: "You still owe on 2 commitments", with no amounts on the lock screen.
- It's skipped with no email gateway, and when the flag or feature is off. A missed month isn't made up later.

## 9. Phases

0. **Reproduce and measure** (§3).
1. **Frame links** (§5.1). Then repeat the recordings before going on, since the list may be much shorter.
2. **Smooth pages** (§5.2–5.5). Start with the icon check; everything else depends on it.
3. **Local assets** (§6) and **install** (§7), in either order. Test the off switch on real devices before any release.
4. **Notifications** (§8) core and connectors. Pilot on the staging copy, with real phones, on both platforms, before production.
5. **Automatic reminders** (§8.8). Independent of phases 1–4, so these can move earlier, since they help people with email alone.

## 10. Tests, hooks and sample data

**Tests**

- **Frame links:** a system test clicks a row link on each index page and asserts arrival with no "Content missing" and no full document load (a marker set on `window` survives).
- **Morph:** on each first-set page, scroll down, perform the action, and assert the scroll position and new content. Calendar still draws. Icons are still `<svg>`, with no re-creation (a marker on the element survives).
- **Sidebar:** survives a visit (marker on the element); is replaced after starting impersonation, and when its items change; the active link updates; the off-canvas closes on phones.
- **Service worker:** the served script for flag on and flag off; the caching allowlist check; manual tests on devices for install, the offline page, a stale version, and the off switch.
- **PushChannel:** each "does nothing" case; job per subscription; 410 deletes the row; retries are limited; no gateway causes no error; the payload has only title and path; a non-local path is refused.
- **Subscriptions:** sign-out deletes; sync never creates or moves; explicit opt-in moves; impersonation refused; another user's row can't be touched.
- **Connectors:** each source sends one push per enabled recipient, and still sends its email when push fails.
- **Form reminders:** sends once inside the window and not before; nothing for 0, no deadline, a closed form, or the flag off; a concurrent job doesn't double-send; a later deadline re-arms it; complete responses get nothing; the job's list matches the manual screen's; history shows "Automatic".
- **Monthly reminders:** one email for someone owing three commitments; none for someone who has met them; an unticked or ended commitment is left out; a second run in the same month sends nothing.
- **Lighthouse or Chrome DevTools** on the staging copy for installability and the §6 numbers, recorded before and after. A manual check, not CI.

**Hooks.** `PushSubscription` and `PushPreference` don't include `CanBeHooked`: they're device plumbing, and a hook's `model` would expose keys to stored code. `Gateway::WebPushGateway` inherits the existing `gateways` hook. No new events. The reminders that trigger a push have their own hooks where they already exist. The two new jobs write no new models; a form reminder is recorded in `form_reminders` as today.

**MCP.** No tools. Sending a push to people from an AI client adds nothing that `create_announcement` doesn't already cover.

**Sample data.** `feature/smooth-pages`, `local-assets` and `turbo-frame-links` need nothing. `installable-app.rb` sets a Northwind short name. `phone-notifications.rb` creates the gateway and preferences for one person, but no subscription, as those only come from a real device. `forms-auto-reminders.rb` sets a Northwind form with a deadline next week to 3 days. `commitment-monthly-reminders.rb` ticks the box on one commitment.

## 11. Decisions

1. **Stay on Hotwire.** The code is built for this and barely uses it. Native wrappers and a separate front end are in the pitch's "if a need appears" list.
2. **Fix frame links in place, as a bug fix with no flag.** It's a 30-line correction to how Turbo Frames should be used, with no change in where a link goes.
3. **Morph is opt-in per page.** Morph can overwrite unsaved input and disturb scripts. Each page is tested before it's added.
4. **The sidebar's id carries a digest of its contents.** That makes stale menus impossible, without having to find each thing that changes them.
5. **Keep Font Awesome's SVG+JS build.** The icon picker depends on it. Handling it in morph is less risky than changing how every icon renders. The icon check (2026-11-08) showed the skip listener can't work and converting incoming icons first keeps every icon in place.
6. **No offline pages.** Cached pages could leave student and family information on shared devices, and keep showing things after access changes.
7. **The service worker caches only digested assets and the offline page,** and the off switch ships in the first version.
8. **Push keys live in a Gateway, not server config.** Same place admins set up email, with no deploy or restart. This changes the pitch's first idea.
9. **Push goes on top of email.** People choose topics. Permission is asked only after someone turns it on.
10. **Automatic reminders are in scope, and opt-in per form and per commitment.** Decided 2026-11-04. They're email first, on their own branches, and nothing sends until a leader sets them. Existing open forms start off. Phone notifications themselves still reach only people who opt in.
11. **Announcements default to off once someone opts in,** since a whole-team announcement can reach many people.
12. **Minors opt in to phone notifications themselves, the same as adults.** Payloads carry no personal details.
13. **Device testing** needs at least one real iPhone (iOS 16.4 or later, installed) and one Android phone.
