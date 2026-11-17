# BL-018: Let features register their own settings and hook events

| | |
|---|---|
| Kind | upstream feature |
| Priority | medium |
| Status | started |
| Added | 2026-10-11 |
| Upstream base checked | `86ab397` |
| Branch | `feature/extension-registries` (from `upstream/main`, commit `6f1c45d`) |
| Upstream issue / PR | none yet. Don't open one until Corey says so. |

## Summary

Every feature that adds a setting or a hookable model has to append a line to two shared lists: the `add_setting` calls at the end of `Settings#initialize` (`lib/settings.rb`) and the targets array in `Hook.catalog` (`app/models/hook.rb`). Two branches that each append there conflict, even though their changes are unrelated. This happened between `feature/forms` and `feature/signups` (hbr.16 preview, 2026-10-11) and earlier between person-fields, forms and widgets on the catalog line.

## The change (on the branch)

- `Settings.register(key, type, name, default, group, description)`: a public class method with the same arguments as the built-in `add_setting`, next to the existing `Settings.register_feature`.
- `GatherPack::HookCatalog` (`lib/gatherpack/hook_catalog.rb`, loaded from `config/application.rb` like `GatherPack::Features`): `register_targets("widgets")` adds `widgets - create/update/destroy`, `register_events("widgets - published")` adds a domain event. `Hook.catalog` appends `HookCatalog.entries` on its last line only, so it doesn't conflict with branches that still edit the list line.
- Tests: `test/models/hook_test.rb`, `test/lib/settings_register_test.rb`.

It works against current `upstream/main` on its own: nothing upstream uses it yet, and no behaviour changes until something registers.

## How the fork uses it

`feature/signups` and `feature/commitments` depend on it and register their settings and hook events from their own initializers, so they don't touch `lib/settings.rb` or `app/models/hook.rb`. `feature/forms`, `feature/person-fields` and `feature/widgets` still edit the lists; move them over when they're next reworked.

## Relation to BL-014

BL-014 proposes building the catalog's table events from the models that include `CanBeHooked`. That would make `register_targets` unnecessary for models, while `register_events` would still be needed for domain events such as `signups - fulfilled`. Propose them together: a model-driven catalog plus `register_events` and `Settings.register`.

## Draft upstream issue

> **Let features and plugins add settings and hook events without editing shared lists**
>
> `GatherPack::Features` lets a plugin register a feature from its own initializer, but its settings still have to be added in `Settings#initialize`, and its hook events in the list in `Hook.catalog`. A public `Settings.register` (same arguments as the built-in settings) and a small `GatherPack::HookCatalog.register_events` would let a feature keep these in its own files. Together with building the catalog from `CanBeHooked` models (separate issue), new models would never need a catalog edit. I have a small PR ready if this is wanted.
