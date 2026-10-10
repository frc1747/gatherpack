# BL-013: Saved settings reach only one server process until a restart

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-09 |
| Upstream base checked | `86ab397` |
| Planned branch | `feature/settings-read-through` |
| Upstream issue / PR | none yet |

## Summary

Each `Settings::Setting` reads its value from the PStore once, when the process boots, and keeps it in `@value`. Saving the Settings page writes the PStore and updates `@value` only in the process that handled the save. Any other Puma worker (or the job process) keeps serving the old value until it restarts.

Production runs `WEB_CONCURRENCY` 2 by default (`docker-compose.production.yml:46`), so after a save, about half the requests use the new value and half the old one. This applies to every setting, including feature toggles: `GatherPack::Feature#enabled?` reads `Settings[:"feature_#{key}"]`.

Found while writing the kiosk spec (`fork/specs/kiosk-spec.md` §5.1), whose auto clock-in period is a setting. Not seen in production yet; we have always restarted after changing feature flags.

## Where things are (upstream `86ab397`)

- `lib/settings.rb:16`: `@value = store.transaction { store.fetch(setting_key, default_value) }`, in `Setting#initialize` (once per process, from `Settings#initialize`).
- `lib/settings.rb:26-32`: `value=` writes the store, then sets `@value` in this process only.
- `lib/settings.rb:34-41`: `value` returns `@value` and never reads the store again.
- `lib/gatherpack/feature.rb:30-32`: `enabled?` → `Settings[...]`.
- `config/puma.rb:38`: `workers_count = Integer(ENV.fetch("WEB_CONCURRENCY", 1))`.

## Proposed fix

Make `Setting#value` read through to the store: `store.transaction(true) { store.fetch(setting_key, default_value) }` (a read-only transaction). PStore reads a small file, so the cost is low for the handful of reads per request. If that matters, cache with the file's mtime: re-read only when `File.mtime("storage/settings.pstore")` changes.

Also create the store thread-safe: `PStore.new("storage/settings.pstore", true)` (`lib/settings.rb:96` passes no flag). Without it, a second Puma thread that enters a transaction on the shared store while another is inside one raises `PStore::Error, "nested transaction"` instead of waiting (pstore 0.2.1, `pstore.rb:556-557`). Reading through on every `Settings[...]` would make that collision routine. Puma runs 3 threads per worker (`config/puma.rb:23-24`).

Routes drawn with `if GatherPack::Features.enabled?(...)` in `config/routes.rb` still need a restart (routes are built at boot). Say so on the Settings page next to feature toggles, or leave it as a known limitation.

## Tests

- Write a value straight to `Settings.instance.store` (simulating another process), then `Settings[:key]` returns it.
- Saving through `Settings[:key] = ...` still works.
- Boolean and default handling unchanged.
- Two threads reading at once don't raise.

## Fork strategy notes

- Generic upstream bug, small, `lib/settings.rb` only. Send it as a direct PR after confirming with Corey.
- Until it lands: kiosk code reads its keys fresh itself (kiosk spec §5.1). After changing any other setting in production, ask Corey to restart (never restart production ourselves).

## Draft upstream issue

> **Settings changes don't reach other Puma workers until restart**
>
> `Settings::Setting` caches its value in `@value` at boot (`lib/settings.rb:16`), and `value=` only updates the process that handled the save. With `WEB_CONCURRENCY` > 1 (the production compose default is 2), other workers keep the old value, including feature toggles, until restart. Reading through to the PStore in `Setting#value` (a read-only transaction, optionally cached by file mtime) fixes it. I can send a small PR with tests.
