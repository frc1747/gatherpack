# BL-014: Hook catalog misses models that fire hooks

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | waiting |
| Added | 2026-10-09 |
| Upstream base checked | `86ab397` |
| Planned branch | `feature/hook-catalog-complete` |
| Upstream issue / PR | none yet |

## Summary

`CanBeHooked` runs hooks whose event is `"<table_name> - create|update|destroy"` for every model that includes it. The Hooks form only offers events from `Hook.catalog`, a hard-coded list that is missing 14 of the 31 hooked models, so their events can't be chosen. Examples: a hook on every time clock punch (`time_clock_punches - create`) or on membership applications.

Separately, `token - activate` is in the catalog but nothing fires it. It looks meant for scanning a Hook's token at the time kiosk, which is unfinished: the kiosk sets `tool = "found_hook"` and has no partial for it (kiosk spec §4.3).

## Where things are (upstream `86ab397`)

- `app/models/concerns/can_be_hooked.rb:4-8`: callbacks per table name.
- `app/models/hook.rb:7-15`: `catalog` lists announcements, badges, badge_assignments, events, checkins, memberships, people, relationships, teams, users, pages, tokens, ledgers, ledger_entries, ledger_ownerships, ledger_taggings, ledger_tags, plus `token - activate`.
- Including `CanBeHooked` but missing from the catalog: `budgets`, `budget_periods`, `checkin_field_responses`, `gateways`, `ledger_entry_links`, `ledger_entry_linkings`, `mailboxes`, `mailbox_assignments`, `mailbox_messages`, `membership_applications`, `questions`, `replies`, `time_clock_periods`, `time_clock_punches`. Check with `git grep -l "include CanBeHooked" app/models`.

## Proposed fix

Build the catalog from the models instead of a list: eager-load models, take `ApplicationRecord.descendants.select { _1.include?(CanBeHooked) }.map(&:table_name)`, keep the domain events (`token - activate`) as an explicit list. That also ends the merge conflicts on the catalog line between our branches (person-fields, forms and widgets all edit it), because new models would appear on their own. This is the "way to register hook events" seam noted in the upstream-divergence memory.

Smaller alternative: add the 14 names to the list.

## Tests

- Every model that includes `CanBeHooked` has its three events in `Hook.catalog`.
- `token - activate` is still listed.

## Fork strategy notes

- Upstream bug with a seam we want. Confirm with Corey before any issue or PR.
- Our branches' catalog edits (person-fields, forms, widgets) would drop out once a model-driven catalog lands.

## Draft upstream issue

> **Hook catalog is missing events for 14 hooked models**
>
> `CanBeHooked` fires `"<table> - create/update/destroy"` for every model that includes it, but `Hook.catalog` is a fixed list, so hooks on time clock punches, membership applications, mailboxes and others can't be selected. Building the catalog from the models that include `CanBeHooked` keeps it complete as models are added. Also, `token - activate` is listed but never fired. I can send a PR for the catalog.
