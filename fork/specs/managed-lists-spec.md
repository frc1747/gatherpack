# Managed lists

Status: built. In production since hbr.48, with lists registered by Inventory (place types, stock units, part conditions, reading types) and Orders (approval steps, payment methods, delivery problems).

Rule: AGENT.md rule 13; fork-spec "Defined things". Branch `feature/managed-lists` (depends on `feature/recurring-routes-seams`), no flag (changes nothing until a feature registers a list).

## What it is
A seam for the small tables of things a group names: units, types, conditions, payment methods. A feature adds a table with `name, plural, key, position, active` (plus its own columns), a model that `include ManagedList` and declares `managed_list uses: { table: :column }`, and a `GatherPack::ManagedLists.register(...)` call.

## Behavior
- Order: new rows go last; up and down buttons reorder active rows.
- Retire and restore: retired rows leave pickers but stay on records that use them (the picker shows the current one as "Name (retired)").
- Delete only when unused and not keyed; otherwise Retire, or Merge into another row (repoints every use, audited, then deletes).
- Names are unique per list, ignoring case. `key` marks a row code relies on: never editable on screen, can't be deleted or merged away.
- `seed_defaults!(rows)` fills an empty list once (migrations and seeds).

## Screens
- Setup page: a button per list under its `setup_section` heading, shown to people who may manage it, hidden while the owning feature is off. Orders and Inventory share the heading "Orders and Inventory".
- `/lists/<key>`: description, active and retired rows, New, Edit, up/down, Retire/Restore, Delete or Merge into. 44 px targets.
- Pickers: `managed_list_select f, :column, list: :key` with a "Manage <things>" link for managers.

## Access
Admins, plus anyone the registration's `policy:` allows.

## Hooks
None: these tables are vocabulary, not events; changes are audited by PaperTrail.

## Uses
Inventory: place types, stock units, part conditions, reading types. Orders: payment methods, delivery problem kinds, approval steps.
