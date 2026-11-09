# BL-036: Six admin list pages raise a Ransack allowlist error

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | new |
| Added | 2026-11-08 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Planned branch | none yet |
| Upstream issue / PR | none |

## Summary

`/event_types`, `/hooks`, `/mailboxes`, `/reports`, `/team_types` and `/variables` raise "Ransack needs <Model> associations explicitly allowlisted" at the first `f.input`, in the test environment. None of those models defines `ransackable_associations`. Likely from the Ransack v6 upgrade (`30256e1a`). Not yet checked in production mode.
