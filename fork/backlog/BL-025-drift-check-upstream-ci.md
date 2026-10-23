# BL-025: The drift check doesn't notice when upstream itself is broken

| | |
|---|---|
| Kind | fork-only |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-23 |
| Upstream commit checked | `cee510d` (`upstream/main`) |
| Planned branch | none (`hbr/platform`: `.github/workflows/hbr-drift.yml`) |
| Upstream issue / PR | none |

## Summary

Upstream's CI on `main` has been red since 2026-10-22: the ransack 6 commit (`30256e1`) failed lint and tests, and the merge of PR #518 went in on top of it. Our daily drift check failed too, but only says our rebuild failed, so nobody could tell that the cause was upstream until the 2026-10-23 sync dug through it.

## Fix in mind

In `hbr-drift.yml`, before the rebuild, read upstream's latest push run on `main` (`gh run list -R GatherPack/gatherpack --branch main --event push --limit 1 --json conclusion,headSha,displayTitle`) and put it at the top of the issue the job opens: "upstream `main` at `<sha>` is red in its own CI (lint, test)". When upstream is red and our rebuild fails, the issue should say so first, so the triage starts from "reproduce on plain `upstream/main`" (`fork/STRATEGY.md`, "When upstream is broken").

## Testing

Run the workflow by hand (`workflow_dispatch`) while upstream is red and check the issue text; then on a green upstream, check the line says green.

## Strategy fit

Fork-only CI on `hbr/platform` (a workflow change: ask Corey before pushing it). Nothing for upstream.
