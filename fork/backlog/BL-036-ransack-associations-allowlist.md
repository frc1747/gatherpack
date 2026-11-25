# BL-036: Six admin list pages raise a Ransack allowlist error

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | shipped hbr.23 (fixed by `fb41f4f3` "Default ransackable_associations to none" on `feature/ransack-associations-default`; see `FORK.md`) |
| Added | 2026-11-08 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Planned branch | `feature/ransack-associations-default` |
| Upstream issue / PR | none |

## Summary

`/event_types`, `/hooks`, `/mailboxes`, `/reports`, `/team_types` and `/variables` raise "Ransack needs <Model> associations explicitly allowlisted" at the first `f.input`, in the test environment. None of those models defines `ransackable_associations`. Likely from the Ransack v6 upgrade (`30256e1a`). Not yet checked in production mode.

## Status note (2026-11-15)

This is the bug `feature/ransack-associations-default` already fixes: it defaults `ransackable_associations` to `[]` in `ApplicationRecord`, and its `test/controllers/search_forms_test.rb` renders all six pages (and the other search pages). The branch is current with `upstream/main` `eeaa691a`, which still has the bug. Nothing new to build; it's ready to offer upstream when Corey says so.
