# Spec: Inventory

Status: draft. Nothing is built.

`feature/inventory` knows nothing about orders. The companion spec is [`orders-spec.md`](orders-spec.md); its §4 is the outline this spec fills in, and its §5 is the bridge, `feature/order-inventory`.

## 1. Purpose

A team keeps parts and supplies in a shop: screws in bins, wire on a shelf, batteries in a cabinet. People need to know what there is, where it is, and when to buy more. Today that lives in people's heads, a spreadsheet nobody updates, or a whiteboard.

Inventory records **items** (kinds of things kept), **locations** (nested places), and **stock movements** (every change to how many of an item are at a location). Stock is the sum of the movements. Items at or below their reorder point appear on a **reorder list**.

Most people who use it are high-school students on a phone, standing at a bin. The frequent actions (record what was used, count a bin, find where something is) must take a few taps.

Three layers, as in the orders spec:

- **Order requests** (`feature/orders`).
- **Inventory** (`feature/inventory`, this spec). Works on its own.
- **Order receiving into inventory** (`feature/order-inventory`). The only branch that knows both.

### 1.1 Scope

| Use case | Verdict | How |
|---|---|---|
| Find where a part is kept | Fits | Search by name, part number or category; each result shows its locations and counts (§3.9) |
| A student takes 4 screws from a bin | Fits | **Used** on the bin or item page, quantity, done (§3.9) |
| Count what's in a bin and fix the number | Fits | **Count**: type what you see; a `counted` movement records the difference (§3.3) |
| Move stock from one cabinet to another | Fits | **Move**: one movement out, one in (§3.3) |
| Parts arrive from a vendor | Fits | **Received** by an inventory manager, with an optional note of where from (§3.3). With orders, receiving a delivery does it (orders spec §5). |
| A sponsor donates a box of parts, or a part turns up | Fits | **Added** with a reason (§3.3) |
| Something breaks, is lost or thrown out | Fits | **Removed** with a reason (§3.3) |
| Know what to buy before running out | Fits | Reorder point and reorder quantity per item; the reorder list (§3.5) |
| Tell the people who buy when stock runs low | Fits | Notice to inventory managers, daily digest by default (§3.12); hook event (§7) |
| Turn the reorder list into an order request | Additive | `feature/order-inventory` adds **Order these** through the reorder action seam (§3.8) |
| Know which vendor sells an item and its part number there | Fits | Item sources: free-text vendor name, part number and link (§3.1). With orders, the bridge links a source to a vendor record. |
| Print bin labels | Fits | Label sheet with name, code and a QR code that opens the location's page (§3.10) |
| Two teams share one shop | Fits | Items and locations belong to a team; an item on a parent team is shared by its subteams (§3.6) |
| A motor goes on the robot, comes off for a rebuild, sits in a bin, and goes onto the practice robot | Fits | Tracked item: each piece is a **unit** with its own label; installing and taking off are unit moves between a bin and a **machine** (§3.15) |
| Know what's on a robot right now | Fits | The machine's page lists its installed units, with condition (§3.15) |
| Know the condition and history of one part (a battery's age and resistance, a gearbox that's been rebuilt twice) | Fits | Unit condition, checks with readings, and a unit history (§3.15) |
| A swerve module, with its motors, moves from one robot to another | Fits | A unit can be installed in another unit; its parts go with it (§3.15) |
| Don't put a broken part on the competition robot | Fits | Installing a unit marked Needs repair or Broken asks for a confirm and is flagged on the machine page; it's not blocked (§3.15) |
| Lending tools to members (check out, due back) | Non-goal here | A separate feature; tracked units and their history are what it would build on |
| Value of stock, cost accounting | Non-goal | Inventory counts things. Prices live in orders and the ledger. |
| Fractional quantities (3.5 ft of wire) | Non-goal | Whole numbers in one stock unit; pick a smaller unit (inches) when it matters (§3.1) |
| Barcode scanning of manufacturer barcodes | Non-goal | Our own QR labels open pages with the phone's camera app; no in-app scanner |
| Importing an existing spreadsheet | Additive | A CSV import of items with a starting count, recorded as `added` movements (§3.11) |

## 2. Concepts

| Concept | Meaning |
|---|---|
| Item | A kind of thing kept: "M4 × 12 socket head screw", not one particular screw. Counted in one stock unit. |
| Item source | Where an item can be bought: vendor name, the vendor's part number, a link. An item has any number. |
| Location | A place things are kept. Nested: shop → cabinet → bin. |
| Stock movement | One change to the quantity of an item at a location, with a kind, who, when and why |
| Stock | The quantity of an item at a location: the sum of its movements. An item's total stock is the sum over all locations. |
| Reorder point | When total stock is at or below this, the item is on the reorder list |
| Reorder quantity | How many to buy when it is |
| Tracked item | An item whose pieces are kept apart, each as a unit, because they're reused and worth following (motors, controllers, batteries, modules) |
| Unit | One piece of a tracked item, with its own label, condition and history |
| Machine | A location that is something built and run, not a shelf: a robot, a practice base, a demo board. Units are installed on it. |
| Inventory manager | A person allowed to manage items and locations for teams within their reach, granted by badge (§3.6) |

## 3. Inventory (`feature/inventory`)

### 3.1 Model

- **Item.** `team` (whose item; §3.6), `name`, `description`, `category` (free text with suggestions from existing categories), `manufacturer`, `manufacturer_part_number`, `unit` (the stock unit: "each", "ft", "pack"; default "each"), `home_location` (optional: where it usually lives, the default for Used and Received), `reorder_point` (optional whole number), `reorder_quantity` (optional whole number), `url`, `note`, `active`, optional photo. Quantities are whole numbers in the stock unit. Inactive items keep their history and drop out of search and the reorder list.
- **Item source.** Belongs to an item. `vendor_name` (free text), `vendor_part_number`, `url`, `preferred` (at most one per item), `note`, `position`. No vendor table: inventory works without orders. `feature/order-inventory` adds a nullable `vendor_id` to this table with its own migration and fills it by matching names and link domains (§3.8).
- **Location.** `team`, `parent` (blank for a top-level place), `name` ("Cabinet A", "Bin 3"), `code` (short label text, unique within the top-level place, for example "A-3"), `note`, `position`, `active`. A new location takes its parent's team. Its full name is the path: "Build shop › Cabinet A › Bin 3". Depth is not limited. A location can hold stock and other locations at the same time (a shelf with loose rolls of wire and bins on it). A location with stock can't be made inactive or deleted; move or remove the stock first.
- **Stock movement.** `item`, `location`, `kind` (§3.3), `quantity` (signed change: + in, − out), `counted_quantity` (for counts: what the person saw), `person` (who did it), `recorded_by` (who entered it, when different: a manager entering for a student), `reason` (short text), `note`, `move_group_id` (pairs the two rows of a move), `reverses_id` (for an undo), `created_at`. Movements are never edited or deleted, including by admins.
- **Stock level.** `item`, `location`, `quantity`. A cache of the sum of movements, written in the same transaction as each movement so lists don't add up history on every page. A rake task rebuilds it from movements and reports any difference. The movements are the record; the level is only for speed.

Plain table names, as upstream uses and as orders does (`vendors`, `purchases`). Upstream's `db/schema.rb` has no `items`, `locations`, `item_sources`, `stock_movements` or `stock_levels` table, and the app has no `Item`, `Location` or `StockMovement` class. (`events.location` is a column, not a table.) If upstream adds one of these names before this lands, ours takes an `inventory_` prefix.

### 3.2 Who records what

Each movement kind has a fixed list of who may record it. Members' kinds are a setting, because teams differ on whether students should fix counts.

| Kind | Means | Who | Quantity |
|---|---|---|---|
| `used` | Taken out and used up | Members (§3.6) | − |
| `moved` | From one location to another (two rows) | Members | − at one, + at the other |
| `counted` | Someone counted what's there | Members | Counted minus current stock |
| `received` | Arrived from a vendor | Inventory managers | + |
| `added` | Donated, found, or the first count when setting up | Inventory managers | + |
| `removed` | Broken, lost, thrown out, given away | Inventory managers | − |

The setting `inventory_member_kinds` lists the kinds members may record. Default: `used`, `moved`, `counted`. Inventory managers and admins may record every kind. A team that wants only managers to count takes `counted` out of the setting.

### 3.3 Movements in detail

- **Used.** Item, location (defaults to the item's home location, or the only location with stock), quantity (default 1). Reason optional ("What for?"), unless `inventory_used_needs_reason` is on.
- **Moved.** Item, from, to, quantity (default: all of it). Writes two rows with the same `move_group_id`. History shows them as one line.
- **Counted.** Item, location, the number seen. The movement's `quantity` is that number minus the stock at that moment, and `counted_quantity` keeps what was seen. A count that matches writes a movement with quantity 0: it still records that someone checked, and when. "Last counted" on the item and location pages comes from it.
- **Received, added, removed.** Item, location, quantity, reason. Received has an optional "From" (free text, suggested from the item's sources).

**Going below zero.** Recording more used or moved than the stock shows is allowed. Records are often behind, and a student at the bin shouldn't be stopped. The location then shows "Needs a count", and the item and bin pages offer **Count now**. Lists treat negative stock as zero for the reorder total.

**Undo.** The person who recorded a movement sees **Undo** on it for 10 minutes. Inventory managers can undo any movement at any time. Undo writes a reversing movement of the same kind with the opposite quantity and `reverses_id` set; the original stays. History shows both, marked "Undone". Undoing a count reverses its difference.

**Locking.** Recording a movement locks the stock level row for that item and location (creating it if needed), so a count and a used at the same moment both land correctly. A count's difference is worked out inside the lock.

### 3.4 Stock and reorder arithmetic

- Stock at a location = sum of that item's movements there.
- Total stock = sum over all active locations, negatives counted as zero.
- An item is **low** when it has a reorder point and total stock ≤ reorder point. An item without a reorder point is never low.
- Out of stock = total stock 0.
- **On order** comes from the on-order seam (§3.8). With nothing registered it's zero and not shown.
- An item is on the reorder list when total stock plus on order ≤ reorder point. This keeps an item off the list once enough is ordered.
- **Suggested quantity** on the list: the reorder quantity, or, when blank, enough to get back to twice the reorder point. The person can change it before acting.

### 3.5 The reorder list

One page, **Reorder**, for inventory managers and admins, listing items within their reach that are low.

- Grouped by preferred source's vendor name; items with no source in "No source yet", at the top.
- Each row: item, total stock, reorder point, on order (when known), suggested quantity, preferred source with its part number and link, and a tick box.
- Out of stock items first within a group.
- Actions on ticked items come from the reorder action registry (§3.8). Inventory itself registers two: **Print** (shared report print CSS) and **Download CSV** (item, part numbers, vendor, vendor part number, link, quantity). `feature/order-inventory` adds **Order these**.
- A filter by team (for someone whose reach covers several) and by category.

### 3.6 Teams, grants and who sees what

**Items and locations belong to a team.** A team's items and locations are visible to everyone in `person.all_team_ids` of that team, which (as upstream defines it) includes the person's own teams, the teams above them, and teams below ones they manage. So an item on a top-level team is shared by every subteam, and an item on a subteam stays with that subteam. "Organization-wide" is an item on a top-level team. A location and the items in it don't need the same team: a subteam's item can sit in a shop that belongs to the parent team.

A movement needs both the item and the location to be visible to the person.

**Inventory managers.** A setting, `inventory_managers`: a list of badge → team pairs, as for orders. A holder manages items and locations on the named team and every team below it, whatever teams they're in; no team named means every team (since hbr.42). Set on Inventory setup (an Inventory button under Purchasing on the main Setup page since hbr.45, admins only) with who can use inventory and running-low notices. Several pairs give the union. Managers of a team and admins can always manage its inventory.

`Inventory::Reach` implements it. It has the same shape as `Orders::Reach` and the sign-ups organizer grant, so the three can later be merged without changing behavior. Inventory doesn't depend on orders or sign-ups to do this; it carries its own copy.

**Who can use inventory at all.** A setting, `inventory_users`: a list of teams whose members (and their subteams) can see and record. Default: blank, meaning everyone signed in. A group that keeps parents or guardians on their own team leaves that team out.

| Who | Sees | Can |
|---|---|---|
| Member in `inventory_users` | Items and locations of their teams (as above), stock, history of those items | Record the kinds in `inventory_member_kinds`; undo their own for 10 minutes |
| Inventory manager | Everything within reach, the reorder list | Every kind; create and edit items, sources and locations; undo any; print labels; import |
| Team manager, admin | Everything for their teams | Everything |

History shows who recorded each movement by name. Nothing else about a person is shown.

### 3.7 Settings

Registered through `Settings.register` (from `feature/extension-registries`), in `config/initializers/inventory.rb`.

| Setting | Meaning | Default |
|---|---|---|
| `feature_inventory` | Feature flag (auto-created by `GatherPack::Features.register`; referred to as `inventory_enabled` in planning) | off |
| `inventory_users` | Teams whose members can use inventory | blank: everyone signed in |
| `inventory_managers` | Badge → highest team pairs (§3.6) | none (admins and team managers only) |
| `inventory_member_kinds` | Movement kinds members may record (§3.2) | used, moved, counted |
| `inventory_used_needs_reason` | Used needs a "What for?" | off |
| `inventory_undo_minutes` | How long the recorder can undo their own movement | 10 |
| `inventory_reorder_notice` | When managers hear an item went low: `off`, `each`, `daily` | daily |
| (list) Stock Units | An item's stock unit is a row of Stock Units on Setup (each, box, pack, roll, foot, set to start; exactly one default, which new items take; the default can't be retired) | each |

The flag gates everything: with it off, controllers redirect (forms' pattern), the menu entries disappear, and no notices or hooks fire from inventory's own events.

### 3.8 Seams this layer offers

Inventory knows nothing about orders. Other features attach through:

- **Hooks** (§7).
- **Notifications.** `stock_movement_recorded.gatherpack`, published after the transaction commits, with `movement`, `item`, `location`, `kind`, `quantity`, `person`, `stock_after` (at the location), `total_after`, and `went_low` (true when this movement put the item on the reorder list). Follows `person_field_changed.gatherpack`. A move publishes one event per row.
- **Registry: `Inventory.extensions`**, shaped like `Signups.extensions`:
  - `register_reorder_action(key, label:, path: ->(items_with_quantities){}, visible: ->(person){})`. A button on the reorder list. It receives the ticked items and the quantities shown, and returns where to go. `feature/order-inventory` registers **Order these**, which calls `OrderRequest.draft_for` and opens the draft.
  - `register_on_order(callable)`. Called with a list of items, returns `{ item_id => quantity }` on order. Summed when several are registered. `feature/order-inventory` registers one counting ordered, not yet received lines that carry the item, times `units_per`.
  - `register_item_panel(key, partial:, visible:)`. A panel on the item page. `feature/order-inventory` adds "Recent orders" for the item.
  - `register_source_fields(key, partial:, permit:)`. Extra fields on the item source form. `feature/order-inventory` adds the vendor picker for its `vendor_id` column.
- **Recording movements.** `StockMovement.record!(kind:, item:, location:, quantity:, person:, reason: nil, note: nil, recorded_by: nil, to_location: nil)` is the supported way for another feature to change stock (the receiving extension in `feature/order-inventory`). It runs the same permission check as the page unless the caller passes `authorized_by:` (the policy decision it already made), takes the lock, writes the movement and level, and publishes the notification.
- **Lookup.** `Item.search(query, viewer:)` (name, part numbers, category, source part numbers), used by the bin page and by `feature/order-inventory`'s **Pick from what we stock**.
- **Item attributes for other features.** `Item#line_attributes` returns description, manufacturer, part numbers, unit and the preferred source's name, part number and link, as plain keys. The bridge maps them to an order line. Inventory doesn't know what an order line is.

### 3.9 Experiences

**Words on screen.** Plain words; the model keeps its names.

| In the model | On screen |
|---|---|
| Item | Item (or "Part" where the label is short) |
| Location | Place |
| Stock movement | Change |
| `used` | Used |
| `moved` | Moved |
| `counted` | Counted |
| `received` | Received |
| `added` | Added |
| `removed` | Removed |
| Reorder point | Order more at |
| Reorder quantity | Order how many |
| Item source | Where to buy |
| Low | Running low |
| Negative stock | Needs a count |

**Phone-first screens.** Inventory home, search results, the item page, the place page, and the Used, Count and Move forms must work one-handed on a phone: one column, buttons at least 44 px tall, the main action in a bar fixed to the bottom, number entry with a large − / + stepper and the number keypad. Items, Places (editing), Reorder, Labels and Import are built for a desktop and only need to be readable on a phone.

**Find something.**
1. **Inventory** opens with a search box at the top, focused.
2. Typing searches name, part numbers and category. Each result shows the item and, under it, where it is and how many: "Build shop › Cabinet A › Bin 3: 14". "Running low" and "Needs a count" show as badges.
3. Tapping a result opens the item page: photo, stock by place, last counted, where to buy, history, and the buttons **Used**, **Count**, **Move**.

**At a bin.**
1. Scan the label's QR code with the phone's camera. It opens the place's page (signing in first if needed).
2. The page lists what's in the place with counts, and the places inside it.
3. Each row has **Used** and **Count**. **Count this place** steps through every item in it, one screen each: the number shown is blank (so people count rather than confirm), type what you see, **Next**. At the end, a summary of differences and **Save counts**.

**Record used.**
1. **Used** on an item or a place row.
2. Quantity, with the stepper, default 1. "From" is preset and changeable when the item is in more than one place.
3. **What for?** collapsed and optional (required when `inventory_used_needs_reason`).
4. **Done.** A toast with **Undo**.

**Manager: set up.**
1. **Places**: build the tree (shop, cabinets, bins), set codes, print labels.
2. **Items**: add items with unit, home place, reorder point and quantity, where to buy. Or import a CSV.
3. First counts: **Added** with reason "Starting count", or the import does it.

**Manager: keep it running.** **Reorder** (§3.5). **Changes**: all movements within reach, filtered by kind, place, person and date, with counts that changed stock by more than 20% highlighted. Prints and downloads as CSV.

### 3.10 Labels

A label sheet for selected places: place name, code, full path in small print, and a QR code of the place page's URL. Item labels show name, part number, and the QR code of the item page. Sizes for common sticker sheets are a print stylesheet choice, not a setting. QR codes are generated as SVG with the `rqrcode` gem (pure Ruby), added to the Gemfile.

### 3.11 Import

A CSV upload for inventory managers: name, category, manufacturer, manufacturer part number, unit, vendor, vendor part number, link, place code, quantity, reorder point, reorder quantity. A preview shows what will be created and any rows with an unknown place code. Each row with a quantity writes an `added` movement with reason "Imported". Rows matching an existing item by manufacturer part number, or by name when there's none, update it rather than duplicating. Import is the only bulk write.

### 3.12 Notices

Mailer and reminder pattern as in forms and sign-ups, so notices reach people on whatever channels that pattern delivers to.

| When | Who |
|---|---|
| An item goes on the reorder list | Inventory managers within reach of the item's team, per `inventory_reorder_notice` (daily digest by default) |
| A count changes stock by more than half | Inventory managers within reach, in the same digest |

Members get no notices. The daily digest is a recurring job in `config/recurring.d/inventory.yml` (from `feature/recurring-routes-seams`); it sends nothing when the flag is off or nothing changed.

### 3.13 Menu

Inventory always has its own menu heading, **Inventory** (since hbr.46; until then it joined a shared Purchasing heading when orders was on, which mixed the two). `Inventory::Feature < GatherPack::Feature` stays only to draw the machine item with the group's word (§3.15).

Nav items: Stock (`/inventory/stock`: search and what's on hand), Machines (the group's word; hidden when turned off), Reorder, Items, Places, Changes. Stock has its own path so upstream's prefix highlighting lights only one item; `/inventory` still opens Stock. Inventory setup is a button under an Inventory heading on the main Setup page.

**Home and the member-first menu.** `feature/my-gatherpack-inventory` (from `feature/my-gatherpack` and `feature/inventory`), a connector in the pattern of the orders one: every inventory item stays under the Inventory heading, with no Manage placements or check (since hbr.44). A `:todo` row for inventory managers, **"5 items running low"**, one summary row that opens Reorder. As everywhere in that menu, placements change what's shown, never what's allowed.

### 3.14 Data

| Table | Columns |
|---|---|
| `items` | `team_id`, `name`, `description`, `category`, `manufacturer`, `manufacturer_part_number`, `unit`, `tracked` (boolean), `reading_fields` (jsonb: name and unit of each reading a check asks for), `home_location_id`, `reorder_point`, `reorder_quantity`, `url`, `note`, `active`; photo attachment |
| `item_sources` | `item_id`, `vendor_name`, `vendor_part_number`, `url`, `preferred`, `note`, `position` |
| `locations` | `team_id`, `parent_id`, `name`, `code`, `kind` (`storage`, `machine`), `note`, `position`, `active` |
| `item_units` | `item_id`, `code`, `serial_number`, `name`, `location_id`, `installed_in_id` (nullable, another unit), `condition`, `condition_note`, `in_service_on`, `active`; photo attachment |
| `item_unit_events` | `item_unit_id`, `action`, `from_location_id`, `to_location_id`, `from_unit_id`, `to_unit_id`, `condition_before`, `condition_after`, `readings` (jsonb), `person_id`, `recorded_by_id`, `note`, `created_at`; photo attachment |
| `stock_movements` | `item_id`, `location_id`, `kind`, `quantity`, `counted_quantity`, `person_id`, `recorded_by_id`, `reason`, `note`, `move_group_id`, `reverses_id`, `created_at` |
| `stock_levels` | `item_id`, `location_id`, `quantity`; unique index on the pair |

UUID primary keys and `neat_id` prefixes `itm_`, `isrc_`, `loc_`, `smv_`, `unt_`, `uev_` (confirm these prefixes are free when building). Indexes: `stock_movements (item_id, location_id, created_at)`, `stock_movements (location_id, created_at)`, `items (team_id, active)`, a trigram or `ILIKE` index on `items.name` only if search measures slow. `locations.code` is unique within its top-level place, checked in the model (the top-level place is derived).

All models use `has_paper_trail versions: { class_name: "AuditLog" }`, as upstream models do. Stock movements are their own history and are insert-only; paper_trail on them records the create only.

Migrations are new and reversible. Upstream files touched (estimate): `db/schema.rb`, `Gemfile` and `Gemfile.lock` (`rqrcode`). Routes go in `config/routes/inventory.rb` and the digest job in `config/recurring.d/inventory.yml` (`feature/recurring-routes-seams`). Settings, hook events and the feature registration go in `config/initializers/inventory.rb` (`feature/extension-registries`), so `lib/settings.rb`, `app/models/hook.rb`, `config/routes.rb` and `config/initializers/features.rb` aren't edited.

**Branch base.** `feature/inventory` is based on `feature/extension-registries` and `feature/recurring-routes-seams`, which have no orders code, because upstream itself has neither `Settings.register`, `GatherPack::HookCatalog` nor the routes and recurring seams.

### 3.15 Tracked parts and machines

**Place types (managed list, hbr.48).** What a place does comes from its type, a list admins manage on Setup (Orders and Inventory › Place Types), seeded with Storage (keeps stock) and Machine (parts get installed on it). Code reads the two flags, never the name: `holds_stock` places keep counted stock and spare units; on a `holds_installed_parts` place only units go, each with its own page. Every active type that holds installed parts is a menu entry and a page named by its plural ("Robots", "Practice bases"); `/inventory/machines` opens the first. Renaming a type renames it everywhere; retiring it is "off": no new place takes it, nothing is installed on its places, its menu entry and page go, and its places keep the type, showing as ordinary places that list their parts so they can be taken off. A type's flags can't change while its places rely on them, and one type can't have both.

Some parts aren't used up. A motor goes onto a robot, comes off for a rebuild, waits in a bin, and goes onto the practice robot. People want to know which one is where, what shape it's in, and what's on each robot. Counting them as stock loses all of that, so these items are **tracked**: each piece is a **unit**.

**Tracked items.** An item has `tracked` (default off; an inventory manager turns it on, and it can't be turned off while the item has units). A tracked item has no stock movements of its own. Its stock is worked out from its units:
- **Available** = active units in a storage location, not installed, and not Needs repair or Broken. This is the number the reorder list uses (§3.4), so "2 spare motors left" puts motors on the list.
- The item page shows units by place: available, on each machine, in repair, retired.

Turning tracking on for an item that has stock asks for that many units to be created (with codes to fill in later), so nothing is lost.

**Units.** A unit has a `code` (its label, unique within the item's team: "NEO-07", "BAT-2026-03"), an optional `serial_number` and `name` ("Left front module"), where it is, its `condition`, a `condition_note`, `in_service_on` (when it was first used; defaults to when it was created), `active` and a photo. A unit is in exactly one place: a location, or installed in another unit.

**Machines.** A location has a `kind`: `storage` (the default: shelves, bins, carts) or `machine` (a robot, a practice base, a demo board). A machine is a top-level location or sits under a storage place (the robot cart). Machines get their own list, **Machines**, and a page that lists every installed unit, nested by sub-assembly, with condition. Only units go on a machine; counted stock (screws, zip ties) on a robot is used, not tracked.

**Sub-assemblies.** A unit can be installed in another unit: motors in a swerve module, a module on a robot. Moving the outer unit moves everything in it; each inner unit's history records the move with the outer unit's code. Taking an inner unit out puts it in a location or another unit.

**Conditions (managed list, hbr.48).** Part Conditions on Setup, seeded New, Good, Worn, Needs repair and Broken (both *needs attention*), and Retired (*out of service*). Needs attention: not available, installing asks first, the daily digest lists it. Out of service: drops out of every count, can't be installed. Mark for repair offers the active needs-attention conditions (Needs repair first), Repaired the active ones with neither flag (Good first), Retire sets Retired; each finds its default by key, so renaming keeps it working. A unit is created New.

**Actions on a unit.** Each writes an `item_unit_events` row in the same transaction, with who, when and a note; events are never edited or deleted.

| Action | What it does | Who (default) |
|---|---|---|
| **Install** | Put the unit on a machine or in another unit | Members |
| **Take off** | Back to a storage location (defaults to the item's home location) | Members |
| **Move** | From one storage location to another | Members |
| **Check** | Record the condition, a note, an optional photo, and the item's readings | Members |
| **Mark for repair** | Condition to Needs repair, with what's wrong | Members |
| **Repaired** | Condition back to Good or Worn, with what was done | Inventory managers |
| **Retire** | Condition to Retired, with why | Inventory managers |

Members' unit actions are a setting, `inventory_member_unit_actions` (default Install, Take off, Move, Check, Mark for repair), on the same pattern as `inventory_member_kinds` (§3.2). Undo works as for movements (§3.3): the person who recorded it, for 10 minutes; managers any time; undo writes a reversing event.

**Readings (managed list, hbr.48).** Reading Types on Setup (Hours (h), Cycles, Volts (V) to start); a tracked item ticks the ones its checks ask for. Saved readings are keyed by the type, so renaming one renames it in every history.

**Installing something that isn't right.** Installing a unit marked Needs repair or Broken asks "This unit is marked Needs repair: install anyway?" and records the answer in the event. It's flagged, not blocked, as with going below zero (§3.3). The machine page marks such units at the top.

**Labels and phones.** Units get small labels (code, item name, a QR code that opens the unit page) from the same label sheet as locations (§3.10). The unit page on a phone leads with the actions above as large buttons. A machine's page has its own label, and from it **Install a part** asks for the unit by scanning its label or typing its code.

**Notices.** A unit marked Needs repair or Broken goes into the inventory managers' daily digest (§3.12).


## 4. Hooks

Every new model includes `CanBeHooked`. Register through `GatherPack::HookCatalog` (`feature/extension-registries`):

- Targets: `items`, `item_sources`, `locations`, `stock_movements`, `item_units`, `item_unit_events`. `stock_levels` isn't a target: it's derived, and `stock_movements - create` covers every change.
- Events, fired with `Hook.where(event: …).each { |h| h.run(item) }` as `Signup#run_status_hooks` does, after the movement commits:
  - `items - running_low`: total stock plus on order dropped to or below the reorder point.
  - `items - out_of_stock`: total stock reached zero.
  - `items - restocked`: total stock rose back above the reorder point.
  - `stock_movements - count_differs`: a count's difference wasn't zero; `model` is the movement.

  - `item_units - needs_repair`: a unit's condition became Needs repair or Broken.
  - `item_units - installed`, `item_units - removed`: a unit went onto or came off a machine.

Each stock event fires only on the crossing, not on every movement while low.

## 5. Order receiving into inventory (`feature/order-inventory`)

Specified in [`orders-spec.md`](orders-spec.md) §5. From inventory's side it uses only the seams in §3.8: `register_reorder_action` for **Order these**, `register_on_order`, `register_item_panel`, `register_source_fields` plus its own migration adding `item_sources.vendor_id`, `StockMovement.record!` for received deliveries, `Item.search` and `Item#line_attributes` for **Pick from what we stock**. When orders is present, a `received` movement made through a delivery carries the purchase's vendor name as its "From" and a link back in its note. For a tracked item, receiving creates one unit per piece instead (`ItemUnit.receive!(item:, location:, count:, person:, note:)`), with codes to fill in when they're labelled.

## 6. MCP tools (`feature/mcp-orders`)

Inventory's MCP tools don't live in `feature/inventory`. They're in `feature/mcp-orders`, alongside the orders tools, and appear only while `feature_inventory` is on.

| Tool | Inputs | Result or effect | Mirrors |
|---|---|---|---|
| `list_items` | query, category, team, low only, page | Items visible to the person: name, part numbers, unit, total stock, reorder point, running low | Inventory search, Items |
| `get_item` | item id | The item, its sources, and stock by location with full place names and last counted | Item page |
| `list_locations` | parent (optional), team | Places visible to the person, with path, code and item count | Places |
| `reorder_list` | team, category | Items on the reorder list within the person's reach, with stock, on order, suggested quantity and preferred source | Reorder |
| `record_stock_movement` | kind, item id, location id, quantity (or counted quantity for `counted`), to location (for `moved`), reason, note | Records through `StockMovement.record!`; returns the movement and stock after | Used, Count, Move and the manager kinds |
| `list_machines` | team | Machines within reach, with installed units and any flagged condition | Machines page |
| `get_unit` | unit id or code | The unit: place, condition, latest readings, history | Unit page |
| `record_unit_event` | unit id, action (§3.15), to location or unit, condition, readings, note | Records through the same model method as the unit page; refused where the page would refuse | Unit page actions |

Rules:

- Tools allow exactly what the app allows. They use the same policies and scopes as the pages: a member gets only the kinds in `inventory_member_kinds`; `reorder_list` is refused to anyone the Reorder page refuses.
- `record_stock_movement` also needs the existing `mcp_write_enabled` setting, as every MCP write does.
- One movement per call. Import isn't offered.

## 7. Sample data and tests

**Sample data:** `fork/sample_data/features/inventory.rb`, Northwind. Places: "Build shop" (Northwind's top-level team) with "Cabinet A" (bins A-1 to A-6), "Electrical cart" (drawers E-1 to E-4) and "Wire shelf"; an "Outreach closet" belonging to a subteam. About 25 items across categories (fasteners, electrical, bearings, pneumatics, tools, consumables) with generic manufacturers and part numbers, sources with free-text vendor names, home places and reorder points. History covering every kind: a starting import, used by several sample members, a move between cabinets, a count that matched, a count that found fewer, a removed item with a reason, a received box, a donated box, an undone used. States: two items running low, one out of stock, one with negative stock at a bin ("Needs a count"), one with no source, one inactive, one subteam item stored in the parent team's shop. One sample member holds the inventory manager badge capped at a subteam. Sample people use made-up names from the existing sample set; never real names. Tracked: "NEO brushless motor" (12 units: 8 on two machines, 2 in a bin, 1 Needs repair, 1 Retired), "Swerve module" (4 units with 2 motors each, on "Competition robot"), "12V battery" (10 units, readings "Internal resistance (mΩ)" and "Charge cycles", with a history of checks, one Worn). Machines: "Competition robot" and "Practice robot" on the robot cart, "Demo board".

**Model tests:**
- Stock is the sum of movements; `stock_levels` matches after every kind; the rebuild task finds and fixes a tampered level.
- Count writes counted minus current, including zero; two counts and a used at once all land (lock).
- Move writes two rows with one group; undo reverses both.
- Undo: the recorder within `inventory_undo_minutes`, not after; a manager any time; the original stays.
- Movements can't be updated or destroyed.
- Going below zero is allowed and flags the place; negative counts as zero in the total.
- Reorder: no point means never low; on-order from registered callables keeps an item off the list; suggested quantity with and without a reorder quantity.
- Hook events fire once on each crossing and not again while low; nothing fires with the flag off.
- `stock_movement_recorded.gatherpack` is published after commit with the documented payload, and `went_low` is right.
- `Inventory::Reach`: badge → highest team pairs, union of pairs, team managers and admins.
- Visibility: an item on a top-level team is seen from a subteam; a subteam's item isn't seen from a sibling; `inventory_users` excludes a team.
- Member kinds follow `inventory_member_kinds`; a member can't record `removed` by default.
- Location code unique within its top-level place; a place with stock can't be deactivated.
- Menu: `Inventory::Feature#nav_section` is "Inventory" whether or not a feature with Purchasing items is enabled; on `/inventory/machines` only Machines is highlighted.
- Import: preview, create, update by part number, unknown place code reported, `added` movements written.

**Tracked units (model tests):** available count excludes installed, Needs repair, Broken and Retired units, and drives the reorder list; installing an outer unit carries its inner units and writes an event for each; a retired unit can't be installed; installing a Needs repair unit needs the confirm and records it; members can't do actions outside `inventory_member_unit_actions`; undo writes a reversing event; turning tracking on creates units for existing stock and turning it off is refused while units exist; codes are unique within a team; the `needs_repair`, `installed` and `removed` hooks fire once.

**Tracked units (system tests, phone-sized):** open a unit from its label link, take it off a machine into a bin, check it with a reading; install a module with motors on a machine and see the machine page list all three.

**System tests (phone-sized screen where marked):**
- Search finds an item by part number and shows its places (phone).
- Record used from the item page, then Undo (phone).
- Open a place page by its URL and Count this place, with one difference (phone).
- Move between places (phone).
- Manager builds a place tree, adds an item, prints labels.
- Reorder list shows low items grouped by vendor name; Print and Download CSV work; a stub registered reorder action appears.

**MCP tests** (on `feature/mcp-orders`): each tool returns only what the person's pages show; `record_stock_movement` is refused with `mcp_write_enabled` off and for a kind the member can't record on the page.

`fork/catalog.yml` and `FORK.md` entries when the branch joins the manifest.
