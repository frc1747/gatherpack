# Slack spec

## Goal
A group that runs its day-to-day talk in Slack connects its workspace once. After that, GatherPack posts each kind of news to the channel the group chooses: announcements to the general channel, order requests to the purchasing channel, running-low items to the shop channel. GatherPack also knows which Slack member each person is, and keeps everyone's GatherPack profile photo the same as their Slack photo, so people set their photo in one place: Slack.

## Use cases
| Who | Today | With Slack |
|---|---|---|
| Leader sending an announcement | Posted to one channel by a hand-written code hook | Posted to whichever channels the announcement's team is routed to, when it starts showing |
| Buyer | Checks the Orders page or waits for email | Sees "New order request: 2 × NEO motor, waiting for approval" in the purchasing channel, with a link to it |
| Shop lead | Running-low email | A post in the shop channel when an item drops below its reorder level |
| Member | Uploads a photo in GatherPack, a different one in Slack | Changes it in Slack; GatherPack's kiosk, rosters and check-ins show the same photo |
| Admin | Matches Slack names to people by eye | A People screen that links them by email and lists the ones it couldn't |

## Decisions
- **One Slack workspace per site.** The connection is a Gateway (`Gateway::SlackGateway`), like email and phone push, so the token and signing secret sit in the encrypted `secrets` store, never in the audit log. Only one may exist (same guard as `Gateway::WebPushGateway`).
- **Slack is where photos are changed.** On Slack Pro, the API only lets a person set their own Slack photo, so pushing GatherPack photos into Slack would need every person to authorize GatherPack one at a time. Copying from Slack needs only the bot token and covers everyone. So the default is to copy from Slack, and nothing is written back to Slack. A site with no Slack photos in use can turn copying off (see Settings).
- **The only path from GatherPack to Slack is one-time and by hand.** A linked person who has a GatherPack photo and the default Slack picture sees "Your photo isn't in Slack yet. Download it and set it as your Slack photo." with a **Download photo** link on their profile edit page. Once they set it in Slack, copying takes over.
- **What can be posted is registered by features. Where it goes is data.** Each feature registers its post kinds in code, because each kind is tied to code that builds it. Admins add, edit and remove the routes that send a kind to a channel. A kind can go to several channels (each route posts), and a route can be limited to one team.
- **Posts are read-only.** Each post links back to the record in GatherPack ("Open in GatherPack" button, a plain URL button). Approving or acting from inside Slack is not part of this feature, so no interactive endpoint is needed.
- **Posts are sent from a job**, one `PostToSlackJob` per route and message, so a slow or failing Slack never holds up a save. On Slack's rate limit (HTTP 429), the job raises `Gateway::RateLimited` and retries after `Retry-After`. Other errors are recorded on the route and shown on the Channels screen. The job does not retry them.
- **Member-written text is escaped** (`&`, `<`, `>`) before it goes into a Slack message, so a title can't contain an `@channel` or a link in disguise.
- **Linking is automatic by email, and can be done by hand.** A Slack member links to the one person whose email, or any of whose login emails, matches the member's email (case-insensitive). If the email matches no one, or more than one person (guardians who share an email address), the member is left unlinked for an admin. Links an admin makes or removes by hand are never undone by the automatic linking.
- **Slack events keep photos current. A nightly sync covers anything missed.** If Slack can reach the site, `user_profile_changed` and `team_join` events arrive at `/slack/events` and are handled within a minute. If they don't arrive (the site isn't reachable, or events were never set up), the nightly sync still catches up.

## Design

### Connection (`feature/slack`)
- `Gateway::SlackGateway`, registered as `Gateway.register(self, :slack)`.
  - Secrets: `bot_token`, `signing_secret`.
  - Configuration, filled in by `finish_setup` from `auth.test` and `team.info`: `workspace_id`, `workspace_name`, `bot_user_id`.
  - `ready?` = `bot_token` present and `auth.test` succeeded.
  - `finish_setup` checks the token, saves the workspace details and starts the first member sync.
  - `routes` adds "Channels", "People" and "Slack app setup" links to the gateway page.
  - `identifier_icon` "chat".
  - `before_destroy` removes every `slack_members` row. Routes stay, but they can't post until a gateway exists again.
- **Slack app setup** page (`/slack/app_setup`, admins): the steps to create the Slack app, with a Copy button for a generated **app manifest**. The manifest holds the app name (the site title), the bot scopes, the event subscription URL `https://<host>/slack/events`, and the two events.
  - Bot scopes: `chat:write`, `chat:write.public`, `channels:read`, `groups:read`, `users:read`, `users:read.email`, `team:read`.
  - Directions: "1. In Slack, go to api.slack.com/apps, choose Create New App, then From a manifest, and paste this. 2. Install the app to your workspace. 3. Copy the Bot User OAuth Token and the Signing Secret into a new Slack gateway here." Then a **New Slack gateway** button.
- `Slack::Client`: a small wrapper over `Net::HTTP` for the Slack Web API. It handles JSON, the bearer token, Slack's `ok: false` errors and 429s. No new gem.

### People (`slack_members`)
- Columns: `slack_user_id` (unique), `person_id` (nullable, unique where not null), `email`, `display_name`, `real_name`, `photo_url`, `photo_hash` (the Slack `avatar_hash`), `custom_photo` (from Slack's `is_custom_image`), `copied_photo_hash` (the hash last copied into GatherPack), `linked_by` (`email` or `admin`), `ignored` (bots, guests and people who aren't members), `deactivated`, `synced_at`.
- `Slack::SyncMembersJob`, nightly and after setup:
  1. Pages through `users.list`, skipping bots and Slackbot. Each member's row is created or updated. Deleted Slack accounts are marked `deactivated` and their links are kept.
  2. Runs automatic linking for every unlinked row the admin hasn't set by hand.
  3. Runs the photo copy for every linked row.
- PersonMerge: `GatherPack::PersonMerge.register(:slack_members, :person_id, unique_by: [], model: SlackMember)`. If both people are linked, the kept person's link wins and the other row is unlinked.
- **People screen** (`/slack/members`, layer 4, admins): a list page with filters **Not linked** (the default), **Linked**, **Ignored** and **All**, plus Search.
  - Table columns: Slack photo, Slack name, Email, Person, How linked ("By email" / "By an admin").
  - A **Link** action on each row opens a person picker, the one upstream uses for adding team members.
  - **Unlink** and **Ignore** / **Stop ignoring** are in each row's More menu.
  - The filter bar's table actions offer **Sync now**, which runs the sync job and reports "Syncing with Slack. This page updates when it's done."
  - Empty state: "Everyone in Slack is linked."

### Photos
- Setting `slack_photo_source`, registered with `Settings.register`, shown on the Slack settings page as a labelled choice:
  - "Where people change their profile photo": **In Slack: GatherPack copies each linked person's Slack photo** (the default).
  - **In GatherPack: Slack photos aren't copied.**
- **The copy** (`Slack::CopyPhotoJob`, per member) runs when the source is Slack and the row is linked, `custom_photo` is true, and `photo_hash` differs from `copied_photo_hash`.
  - It downloads Slack's `image_original` (falling back to `image_1024`, then `image_512`) and attaches it as the person's `avatar`, checked by the existing 5 MB and image-type validation. Then it sets `copied_photo_hash`.
  - A person whose Slack picture is the default keeps their GatherPack photo. Removing a Slack photo leaves the last copied one in place.
  - The avatar change is saved through the person record, so it shows in the audit log as "Photo copied from Slack".
- **First sync.** Turning on copying, or linking someone, copies right away. That one-time pass makes Slack's photo win wherever the person has set one. The "isn't in Slack yet" prompt covers the other direction.
- **Profile edit.** When the source is Slack and the person is linked, upstream's avatar field on `people/_form` is replaced through `GatherPack::ViewOverrides`.
  - In its place: the current photo, then "Your photo comes from Slack. Change it there and it shows up here within a few minutes." with a link to the person's Slack profile (`https://app.slack.com/team/<slack_user_id>`).
  - If the person has a GatherPack photo but `custom_photo` is false, it also shows the "isn't in Slack yet" line and the Download photo link.
  - Admins editing someone else see the same text, about that person.
  - People who aren't linked upload as they do today.

### Events endpoint
- `POST /slack/events`. No sign-in, no CSRF, and exempt from the site's sign-in redirects.
  - Verifies `X-Slack-Signature` (v0 HMAC-SHA256 of `v0:<timestamp>:<body>` with the signing secret) and rejects timestamps more than 5 minutes old.
  - Answers `url_verification` with the challenge.
  - For `user_profile_changed`, `user_change` and `team_join`, it enqueues `Slack::SyncMemberJob` for that one user (`users.info`, then linking, then the photo copy) and returns 200 at once.
  - Unknown events get 200 and are ignored. A wrong signature gets 401.

### Channel posts
- Registry `GatherPack::SlackPosts`, loaded with `require_relative` like the other registries:
  - `register(key, label:, hint:, teams: false, available: nil)`
  - `deliver(key, message, team_ids: [])`
  - `Message` has `title`, `text` (optional, up to 3 lines), `url`, `fields` (optional label/value pairs) and `link_label` (default "Open in <site title>").
  - `deliver` returns at once when the flag is off or no gateway is ready. Otherwise it finds active routes for the key whose team is empty or in `team_ids`, sends each channel at most once per message, and enqueues `PostToSlackJob`.
- `slack_routes`: `key` (a registered kind), `channel_id`, `channel_name` (cached for display), `team_id` (nullable, "Everyone"), `active`, `last_posted_at`, `last_error`, `position`. It's not a vocabulary, so delete is allowed. Rows whose kind is no longer registered (the feature was turned off) are kept and shown as "Not available while <feature> is off".
- Message format (Block Kit):
  - A section block holding the title in bold and the text.
  - Fields, if any, as a two-column section.
  - A context line: "<site title> · <time>".
  - An actions block with one URL button.
  - The `text` fallback (for notifications) is the title.
- **Channels screen** (`/slack/routes`, layer 4, admins): a list page.
  - Filter card footer: **New channel rule**.
  - Table columns: What (the kind's label and hint), Channel (#name, a 🔒 icon for private), Only for (the team, or "Everyone"), Last post ("Posted 2 hours ago" / "Failed: the app isn't in #shop. Invite it with /invite @<app name>.", which turns `not_in_channel` and `channel_not_found` into words), and On/Off.
  - Each row: **Edit**, and **More** with **Send test post** and **Delete**.
  - Empty state: "Nothing is posted to Slack yet. Add a channel rule to choose what goes where."
- **Channel rule edit page:**
  - "What to post" (radio list of the available kinds, each with its hint).
  - "Channel" (a select of public channels plus private channels the app has been invited to, from `conversations.list`, cached for 10 minutes, with a **Refresh list** link).
  - "Only for this team" (shown only when the chosen kind has `teams: true`; "Everyone" first).
  - "Posting": **On, post here** / **Off, keep this rule but don't post**.
  - Under Channel: "Anyone in the channel sees these posts. Pick a channel whose members should see them."
  - Cancel, Save.

### Kinds
Each kind is registered from its own feature's initializer, guarded by `defined?(GatherPack::SlackPosts)` and that feature's flag, and its label uses that feature's configurable words. Built in to `feature/slack` (upstream features):

| Key | Label | Posted when | Teams |
|---|---|---|---|
| `announcements` | Announcements | the announcement starts showing (at `start_time`; a scheduled job, cancelled if it's deleted first) | the announcement's team |
| `events_new` | New events | an event is created that people can see | the event's teams |
| `events_today` | Today's events | 7:00 site time, when there are any | the event's teams |
| `membership_applications` | Membership applications | someone applies | the team applied to |

In `feature/slack-connectors` (depends on each feature, like `feature/phone-notifications-connectors`):

| Key | Label | Posted when | Teams |
|---|---|---|---|
| `orders_waiting` | Order requests waiting | a request is submitted or comes back for approval | no |
| `orders_done` | Orders decided and delivered | a request is approved, declined or delivered | no |
| `inventory_low` | Running low | an item drops below its reorder level (once until restocked) | no |
| `signups_open` | Sign-up sheets | a sheet opens | the sheet's team |
| `forms_open` | Forms | a form starts taking answers | the form's teams |
| `time_clock` | Clock-ins | someone clocks in or out at a kiosk | no |

A kind posts names and titles, never contact details, notes, answers or amounts beyond what the record's own title shows.

### Settings page
"Slack" setup (layer 4, reached from the main Setup page under its own heading), with link tabs **Channels**, **People** and **Settings**.
- The header states the connection in words: "Connected to <workspace> as @<bot name>" with a link to the gateway, or "Not connected" with a link to **Slack app setup**.
- The Settings tab is an edit page holding `slack_photo_source` (and nothing else for now).

## Flag
`feature_slack`, default off. While off: no Slack setup entry or screens, `deliver` does nothing, the events endpoint answers 404, the nightly sync doesn't run, and `people/_form` is unchanged. Existing Slack code hooks are unaffected. Rollout: once the `announcements` rule is on, the site's own hand-written Slack hook is disabled by an admin.

## Hooks
- `CanBeHooked` on `SlackRoute`, so changes to channel rules can be hooked like other setup records. `SlackMember` is bookkeeping kept in step with Slack and is not hooked.
- Registered event `slack - photo copied` (with the person), so a site can react to a photo change.
- Posting is not a domain event. The domain events it follows (announcement, order, item) are already hookable.

## Words on screen
Feature "Slack". Screens "Slack app setup", "Channels", "People", "Settings". Buttons "New channel rule", "Send test post", "Sync now", "Link", "Unlink", "Ignore", "Download photo". Test post: title "Test post from <site title>", text "Posts for <kind label> will appear here."

## Sample data
No Slack connection, since Demo and test sites have no outside services: `fork/demo_db/anonymize.rb` already disables external hooks, and it removes the Slack gateway too. Northwind sample data includes five channel rules (including one limited to a team and one turned off) and Slack members: eight linked by email, one linked by an admin, two not linked (one with a shared guardian email) and one ignored bot. Those rows keep the Channels and People screens populated, and the header reads "Not connected".

## Tests
- Signature verification (good, bad, stale timestamp) and `url_verification`.
- Linking: single match, no match, shared email, admin overrides kept across syncs, PersonMerge coverage.
- Photo copy: custom vs default picture, unchanged hash skipped, source "In GatherPack" skips, oversize image rejected.
- `deliver`: team filtering, one post per channel, nothing when the flag is off or there's no gateway, text escaped.
- `PostToSlackJob`: 429 retried, `not_in_channel` recorded on the route.
- System tests for the Channels and People screens and the profile edit replacement.
- `Slack::Client` is replaced by a fake that returns recorded Slack responses. No test calls Slack.

## Depends on
`feature/screen-kit` (list/edit partials), `feature/recurring-routes-seams` (nightly sync and 7:00 job in `config/recurring.d/slack.yml`), `feature/person-merge` and `feature/view-overrides`. `feature/slack-connectors` depends on `feature/slack` and on orders, inventory, signups, forms and the kiosk features.
