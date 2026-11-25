# HBR Specs

Designs a worker builds from: what a feature does, its screens, data, settings, hooks and tests, with decisions recorded rather than left open. How to write one is in the `fork-spec` skill. Feature ideas that don't have a spec yet are in [`../pitches/`](../pitches/README.md); bugs and small tasks are in [`../backlog/`](../backlog/README.md).

Each spec's own status line holds the detail (which phases, which branches). [`FORK.md`](../../FORK.md) tracks each branch. The table below is the one-line summary: update it in the same session as the spec's status line.

## Specs

**Being built**: [Accounting](accounting-spec.md), step by step on `feature/accounting` (BL-011).

| Spec | What it covers | Status | Not built |
|---|---|---|---|
| [accounting-spec.md](accounting-spec.md) | Money answers per person (paid, behind, what's due) from QuickBooks, GatherPack ledgers or a spreadsheet; billing later | building | Everything past the read side; not in the build yet |
| [slack-spec.md](slack-spec.md) | Channel posts per kind of news, Slack member linking, photos from Slack, approve from a post, `/gp` | not started | All of it; no branch |
| [app-feel-spec.md](app-feel-spec.md) | Frame links, smooth pages, local assets, installable app, phone notifications, form reminders | shipped hbr.35 | Monthly commitment reminders (branch parked) |
| [checklists-spec.md](checklists-spec.md) | Checklists: conditions and count items, one answer per person, report, profile, kiosk | shipped hbr.34 | — |
| [digests-spec.md](digests-spec.md) | Summaries: one daily email or the Weekly Infodump per person, per-person choice | shipped hbr.46 | Intake (registrations) not connected |
| [intake-checklists-improvements.md](intake-checklists-improvements.md) | Ranked outline of follow-ons to intake and checklists (housekeeping, dates, data quality, events) | partly built | Most items; built ones are listed in its status line |
| [inventory-spec.md](inventory-spec.md) | Items, nested locations, stock movements, reorder list | shipped hbr.41 | — |
| [kiosk-spec.md](kiosk-spec.md) | Time kiosk: scanned person, auto clock-in, scan panels, kiosk devices | shipped hbr.33 | Phase 4 kiosk devices (BL-038 started on `feature/kiosk-devices`) |
| [managed-lists-spec.md](managed-lists-spec.md) | The seam for tables of things a group names (units, types, conditions) | shipped hbr.48 | — |
| [mcp-spec.md](mcp-spec.md) | MCP server: sign-in, tool registry, call log, first tools | shipped hbr.26 | — |
| [mcp-expansion-spec.md](mcp-expansion-spec.md) | The rest of the MCP writes and reads, and what stays out | shipped hbr.26 | — |
| [membership-intake-spec.md](membership-intake-spec.md) | Joining and rejoining a team: registrations, applications, checklist, person merge | shipped hbr.34 | Phase 6: waiting list, delegated organizers, "Sign again", forms age filter |
| [modern-skin-spec.md](modern-skin-spec.md) | View overrides, modern skin, theme palette | shipped hbr.35 | Phase 2 coverage fixes (no branch) |
| [my-gatherpack-spec.md](my-gatherpack-spec.md) | Member menu, Home, Family, phone hours, Activity page | shipped hbr.41 | Splitting My Forms from Manage Forms |
| [orders-spec.md](orders-spec.md) | Order requests: request, approve, buy, receive; bridge to inventory | shipped hbr.51 | — |
| [sample-data-spec.md](sample-data-spec.md) | Northwind sample data in every build, one command | done (fork tooling) | — |
| [screen-standard-spec.md](screen-standard-spec.md) | One layout per kind of screen; reasoning, screen kit, fix-up plan | shipped hbr.52 | Delete its inventory appendix now that BL-062 to BL-073 have shipped |
| [signups-spec.md](signups-spec.md) | Sign-up sheets and commitments (the engine behind count items) | shipped hbr.18 | Completion badge (deferred) |
| [signups-hbr-rollout.md](signups-hbr-rollout.md) | HBR's configuration and move from SignUpGenius | rolled out hbr.17 | — |

## Fields

- **Status**:
  - `not started`: written, no branch.
  - `building`: has a branch, not yet in production.
  - `partly built`: some parts in production, the rest not started; the **Not built** column says which.
  - `shipped hbr.N`: in production; N is the release with the latest part named in the spec's status line.
  - `rolled out hbr.N`: an HBR configuration spec, applied in production.
  - `done`: fork tooling, no release.
- **Not built**: parts the spec describes that aren't in production. A dash means the spec is fully built.

## Adding a spec

1. Follow the `fork-spec` skill; name the file `<feature>-spec.md`.
2. Add a row to the table above, `not started` until a branch exists.
3. When a branch starts, a release ships a part, or a part is dropped, update the spec's status line, this row and `FORK.md` together.
