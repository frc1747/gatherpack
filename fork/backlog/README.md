# HBR Backlog

Work we've found and decided to do later. These are usually upstream bugs or improvements we're holding back so Brad can work through what we've already sent him. Each item has its own file in this folder with enough detail to pick it up cold: what's wrong, how we know, the fix we have in mind, how to test it, and how it fits the fork strategy.

This list is for work that hasn't started. Once an item has a branch, it moves to [`FORK.md`](../../FORK.md), which tracks branches. Then the item's status here becomes `started` and its file links to the branch.

## Items

| ID | Title | Kind | Priority | Status | Added |
|---|---|---|---|---|---|
| [BL-001](BL-001-page-index-permissions.md) | Page list ignores the Viewer setting and leaks content previews | upstream bug (security) | high | waiting | 2026-10-03 |
| [BL-002](BL-002-period-hours-date-bounds.md) | Period hours skip meetings near the period's last day | upstream bug | low | waiting | 2026-10-03 |
| [BL-003](BL-003-attendance-eligibility-badge.md) | Keep a travel-eligibility badge in sync with attendance | fork-only | medium | blocked | 2026-10-03 |
| [BL-004](BL-004-version-in-sidebar.md) | Show the deployed version under "powered by GatherPack" | upstream feature | low | started | 2026-10-03 |
| [BL-005](BL-005-event-delete-with-checkins.md) | Deleting an event that has check-ins crashes | upstream bug | medium | waiting | 2026-10-04 |
| [BL-006](BL-006-team-less-events-hidden.md) | Events with no team are hidden from everyone but admins | upstream bug | medium | blocked | 2026-10-05 |
| [BL-007](BL-007-seeds-badge-before-membership.md) | First boot on a fresh database crashes in db/seeds.rb | upstream bug | medium | waiting | 2026-10-05 |
| [BL-008](BL-008-member-info-access.md) | Restrict Member Info: its own on/off switch, and managers only by default | upstream feature (security) | high | dropped | 2026-10-05 |
| [BL-009](BL-009-person-team-ids-return-records.md) | `Person#all_team_ids` and `#all_ancestor_team_ids` return Team records mixed with ids | upstream bug (latent) | low | waiting | 2026-10-06 |
| [BL-010](BL-010-long-tick-box-lists.md) | Keep long tick-box lists short on the printable list | fork-only | medium | waiting | 2026-10-07 |
| [BL-012](BL-012-kiosk-period-less-punch.md) | Time kiosk crashes for anyone with a punch that has no period | upstream bug | medium | waiting | 2026-10-08 |

## Fields

- **Kind**: `upstream bug`, `upstream feature`, `fork-only` (HBR config, tooling, or content that upstream wouldn't want), or `ops`. Add `(security)` when it exposes data or permissions.
- **Priority**: `high` (fix next time we have capacity; real harm), `medium` (worth doing), `low` (nice to have).
- **Status**:
  - `waiting`: ready to do, deliberately parked.
  - `blocked`: can't start yet; the item says on what.
  - `started`: has a branch; tracked in `FORK.md`.
  - `done`: shipped or fixed upstream. Keep the row and its file for one release cycle, then delete both.
  - `dropped`: decided against it. Record why in the item file.

## Adding an item

1. Copy the layout of an existing item into `BL-NNN-<slug>.md`, using the next number. Don't reuse numbers.
2. Add a row to the table above.
3. Write it for someone who has no memory of the conversation where it came up. Include file paths with line numbers *and* the upstream commit they refer to, since line numbers drift.
4. Leave out production data (names, emails, record contents). Counts and structure are fine.

## Picking up an item

1. Re-check the evidence against current `upstream/main`. Upstream may have fixed it already.
2. Follow [`STRATEGY.md`](../STRATEGY.md): branch from `upstream/main`, add a `FORK.md` row, and confirm with Corey before opening anything upstream.
3. Set the item's status to `started` and link the branch.
