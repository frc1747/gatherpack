# BL-056: Orders and Inventory emails: one model, a site default and each person's own choice

| | |
|---|---|
| Kind | fork-only |
| Priority | high |
| Status | shipped hbr.51 |
| Added | 2026-11-18 |
| Commit checked | `hbr/integration` @ `b251e91d3` (hbr.50) |
| Planned branches | `feature/digests` (personal choice), `feature/orders`, `feature/inventory` |
| Upstream issue / PR | none |

## Summary

Orders and Inventory send email in two different ways. Inventory has a site setting, **Running Low Notices** (Off, An email each time, In the daily digest, In the Weekly Infodump), but nobody can choose for themselves. Orders has no site setting. Its event emails (submitted, approved, ordered, received...) always go out right away, and only buyers have a personal choice, on a **Buying notices** page that covers their daily list alone. Orders' summary can't go in the Weekly Infodump.

Both features should work the same way:

- **Each feature has a site default**, one of: An email each time, In the daily digest, In the Weekly Infodump, Off. The default for both is **In the daily digest**.
- **Each person can override it, per feature**, in an **Email** card on their **Notifications** page (revised: no extra sidebar entry). A person who doesn't choose gets the site's choice. Someone can pick "each time" for Orders and "Weekly Infodump" for Inventory.

## Evidence

- `config/initializers/inventory.rb:82` registers `inventory_reorder_notice`; choices in `app/models/inventory/config.rb:10-12`; the summary section `config/initializers/inventory.rb:166-170`; `Inventory::Digest` (`app/models/inventory/digest.rb`) reports running low, big count differences and units to repair.
- `config/initializers/orders.rb` registers no notice setting. `OrderNotices` (`app/services/order_notices.rb`) sends each event email at once. `Orders::Reminders.buyer_digest` (`app/models/orders/reminders.rb:13`) sends the buyers' daily list, filtered by `OrderNoticePreference` (`digest`, `immediate`, `off`), chosen on `app/views/orders/notice_preferences/edit.html.erb`.
- `lib/gatherpack/digests.rb`: `GatherPack::Digests.register(key, label:, delivery:, build:)` takes the delivery from a site-wide proc only; there's no per-person choice.

## Design

### Summaries seam (`feature/digests`)

- **Choices:** `GatherPack::Digests::DELIVERIES` becomes `each daily weekly off` plus the existing `both` (kept for features that use it, never offered on the personal page). `each` means "no summary section; the feature emails as things happen".
- **Personal choice table** `notice_preferences`: `person_id` (FK, cascade), `key` (the registered digest key, string), `delivery` (string, one of `each daily weekly off`), timestamps; unique on `[person_id, key]`. Model `NoticePreference`. Person merge: the kept person's row wins; rows of the merged-away person move only where the kept person has none.
- **`register(..., personal: true)`** (default true) marks a section that people may choose for themselves.
- **`GatherPack::Digests.delivery_for(key, person)`**: the person's row when Summaries is on and the section is personal, else the site's `delivery`. Features call this to decide whether to email someone right away (`:each`). `daily_content` and `append_weekly` pick sections by `delivery_for` per person, not by the site value.
- **Email notices page** (`/email_notices`, signed in, Summaries on, at least one personal section of an enabled feature): one row per personal section, labelled by the section's label, with radio choices "Use the site's choice (In the daily digest)", "An email each time", "In the daily digest", "In the Weekly Infodump", "Off". Saving "Use the site's choice" deletes the row. Revised: shown as an Email card on the Notifications page where that page takes other features' cards; standalone, reached from the person's own profile page. Directions: "Choose how you hear about each feature. The daily digest comes once a day around 7:00; the Weekly Infodump is the weekly announcements email."
- With Summaries off nothing changes: no page, features use their site setting.

### Orders (`feature/orders`)

- **Site setting** `orders_notices`, "Order Notices", on Orders setup in a new "Email" box: the four choices, default `daily`. Hint: "How people hear about requests: approvers about requests waiting for them, requesters and watchers about their requests, buyers about what's ready to buy. Each person can change this for themselves."
- **What each choice does for a person:**
  - `each`: today's emails, as they happen (every `OrderNotices` event method, and the buyer's approval notice that `immediate` gave).
  - `daily` / `weekly`: no event emails; the person's Orders section in the summary instead.
  - `off`: no Orders email at all.
  - **Always, unless `off`:** "needed within 3 days" (`needed_soon`) goes out right away: it's urgent.
- **The Orders section** (`Orders::Digest`, built per person, empty sections send nothing), up to three parts:
  - "Waiting for your approval": submitted requests on a step the person approves (`Orders::Access#approver_on?`), oldest first.
  - "Ready to buy": `Orders::Reminders.to_buy(access)` for buyers.
  - "Your requests": requests the person made or watches that changed since `since` (approved, changes requested, declined, ordered, backordered, received), one line each with its newest state.
- `OrderNotices#deliver` drops people whose `delivery_for(:orders, person)` isn't `:each` (event methods) or is `:off` (`needed_soon`). With Summaries off the site setting decides for everyone; `daily` then sends Orders' own 7:00 email with the same section (generalizing `Orders::BuyerDigestJob`, renamed `Orders::DigestJob`), and `weekly` behaves as `daily` (no Infodump without Summaries), noted in the hint.
- `GatherPack::Digests.register(:orders, label: "Orders", delivery: -> { Orders::Config.notices }, build: ->(person, since:) { Orders::Digest.section(person, since:) })` guarded by `defined?(GatherPack::Digests)`; the own job stands down when `handles?(:orders)`.
- **Retire the Buying notices page**, its route, controller, policy and links. A reversible data migration copies `order_notice_preferences` into `notice_preferences` (key `orders`: `digest`→`daily`, `immediate`→`each`, `off`→`off`) when that table exists; the old table stays, unread, to be dropped later.

### Inventory (`feature/inventory`)

- `inventory_reorder_notice` keeps its key; its label becomes **"Inventory Notices"** and its hint covers everything inventory emails: items running low, counts that changed a lot, units marked for repair. Default stays `daily`. Each person can change it on Email notices.
- `each`: an email as each happens (running low as today; plus a new email for a big count difference and for a unit marked Needs repair or Broken, to the item team's inventory managers). `daily`/`weekly`: the existing `Inventory::Digest` section. `off`: nothing.
- The per-person decision uses `delivery_for(:inventory, person)` in `InventoryNotices` and in the section build.

## Tests

- Seam: `delivery_for` with and without a row, Summaries on and off, non-personal section; daily and weekly pick sections per person; the Email notices page saves and clears a choice; merge keeps the kept person's row.
- Orders: each choice for approver, requester and buyer; `needed_soon` under `daily`; empty section sends nothing; Summaries off `daily` sends the own email; the old page's route is gone; the data migration maps values.
- Inventory: each choice; per-person override beats the site default; the two new each-time emails.

## Fork notes

- `feature/digests` comes before `feature/orders` and `feature/inventory` in the manifest; the features call the seam only behind `defined?(GatherPack::Digests)`, so no branch depends on another.
- Spec updates: `digests-spec.md` (personal choice, `each`, orders connected), `orders-spec.md` §3.11, `inventory-spec.md` notices.
- HBR rollout: turn on Summaries (`feature_digests`) in production so people can choose; Orders' default is the daily digest, so requesters stop getting each email unless they pick "An email each time".
