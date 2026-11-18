# BL-056: Orders' buyer digest can't go in the Weekly Infodump; it works differently from Inventory's notices

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-18 |
| Commit checked | `hbr/integration` @ `b251e91d3` (hbr.50) |
| Planned branch | `feature/orders` |
| Upstream issue / PR | none |

## Summary

Inventory's running-low summary has a site setting, **Running Low Notices**, with four choices: Off, An email each time, In the daily digest, or In the Weekly Infodump. Orders' summary of approved requests waiting to be bought has none of these. Each buyer picks their own option on a **Buying notices** page (a daily 7:00 email, an email per approval, or none), and the summary can't go in the Weekly Infodump at all. An admin who looks for the setting where Inventory has it won't find one. Summaries (`feature/digests`) was built after Orders. Only Inventory was connected to it; Orders was left as "Next" in the spec and never done.

## Evidence

- `config/initializers/inventory.rb:82` registers `inventory_reorder_notice` "Running Low Notices", with choices `Inventory::Config::REORDER_NOTICE_CHOICES` (`app/models/inventory/config.rb:11-12`). `config/initializers/inventory.rb:166-170` registers the `:inventory` section with `GatherPack::Digests`. `app/jobs/inventory_digest_job.rb:11` stands down when Summaries handles it.
- `config/initializers/orders.rb` registers no notice setting. The buyer digest runs from its own job, `Orders::BuyerDigestJob` (`config/recurring.d/orders.yml`: "at 7am every day"), through `Orders::Reminders.buyer_digest` / `send_digest` (`app/models/orders/reminders.rb:13`, `:54-62`), filtered by each buyer's `OrderNoticePreference` (`app/models/order_notice_preference.rb`: `digest`, `immediate`, `off`).
- The per-buyer choice is on `app/views/orders/notice_preferences/edit.html.erb`, linked as "Buying notices" from the To buy page and the Home orders card.
- `fork/specs/digests-spec.md` (lines 3 and 12) lists "Connected: inventory. Next: orders (buyers), intake (registrations)".

## Fix

Make Orders work the way Inventory does:

- **Site setting** on the Orders settings page: "Buyer Notices", "When buyers hear about approved requests waiting to be bought". It has Inventory's four choices and wording: Off, An email each time (one per approval, as `immediate` does now), In the daily digest (default, matching today's behavior), In the Weekly Infodump.
- **Summaries section:** add `GatherPack::Digests.register(:orders, label: "Orders", delivery:, build:)` in the orders initializer, guarded by `defined?(GatherPack::Digests)`. The section lists what each buyer can buy, built from `Orders::Reminders.to_buy`. `Orders::BuyerDigestJob` stands down when `GatherPack::Digests.handles?(:orders)`, as `InventoryDigestJob` does. With Summaries off, the daily choice keeps sending its own email, as now.
- **Retire the per-buyer page.** Inventory has no per-person choice, and the site setting replaces it. Remove the page, its route, its controller and the two "Buying notices" links. Leave `order_notice_preferences` in place and stop reading it, then drop it in a later reversible migration once no branch reads it.
- **Spec:** move orders to "Connected" in `fork/specs/digests-spec.md`.

## Tests

- Each of the four choices: Off sends nothing; An email each time sends one per approval; daily puts the buyer's section in the combined daily email (Summaries on) or sends its own 7:00 email (Summaries off); weekly puts it in the Weekly Infodump and sends nothing daily.
- Only buyers who can buy something get a section, and an empty list sends nothing.
- The Orders settings page shows the setting. The Buying notices page and its links are gone.

## Fork notes

- Touches `feature/orders` only. `feature/digests` comes before it in the manifest, so no order change is needed. Update `fork/sample_data/features/orders.rb` if it sets buyer preferences.
- Intake (registrations) is the other feature still listed as "Next" in the digests spec. Check it against this pattern when this item ships.
- HBR rollout: set Buyer Notices to "In the Weekly Infodump", and turn on Summaries (`feature_digests`) in production.
