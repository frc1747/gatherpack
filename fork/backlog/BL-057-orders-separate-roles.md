# BL-057: Orders roles: who requests, who approves and who buys are set separately; team managers don't get all three

| | |
|---|---|
| Kind | fork-only (security) |
| Priority | high |
| Status | in progress (tasks 332-333) |
| Added | 2026-11-18 |
| Commit checked | `hbr/integration` @ `b251e91d3` (hbr.50) |
| Planned branches | `feature/orders`, `feature/inventory` |
| Upstream issue / PR | none |

## Summary

Requesting, approving and buying are different jobs, usually done by different people. Today a team manager can do all three for their team, and nobody can turn that off: `Orders::Reach#team_ids` always adds the teams a person manages (`app/models/orders/reach.rb`), and Orders setup says "Team managers can always buy" and "Team managers always approve". The same is true of funding managers and of Inventory Managers (`app/models/inventory/reach.rb`).

Each role should be a list of grants the admin sets. A grant can name **the managers of a chosen team** (the Finance team's managers buy for everyone) or **holders of a badge** (a Buyer badge, an Approver badge), and for which teams. Team managers get a role only through a grant that says so.

## Evidence

- `app/models/orders/reach.rb` `#team_ids`: `person.all_managed_teams.ids + granted_team_ids(person)`; the comment "Admins reach every team, and managers reach the teams they manage".
- `app/models/orders/access.rb:41-66`: approver and buyer checks go through Reach.
- `app/models/approval_step.rb`: approvers are `ApprovalStepApprover` rows with `badge_id` (required) and `team_id`.
- `config/initializers/orders.rb:50-66`: `orders_requesters` (teams), `orders_buyers` and `orders_funding_managers` (badge > team lines).
- `app/models/orders/settings_editor.rb:22-26`: "Team managers can always buy. Also:".
- `app/models/inventory/reach.rb:66-72`, `config/initializers/inventory.rb:54-61`: the same for Inventory Managers.
- Already right: a requester can't approve their own request (`app/models/orders/approval_engine.rb:82`).

## Design

### A grant row

Every role is a list of rows, read as "any of these". A row says **who** and **for which teams**:

| Who | For |
|---|---|
| Holders of badge B | team T and the teams below it, or every team |
| Managers of team M (M's own managers only, not those of teams above or below it) | team T and the teams below it, or every team |
| Managers of the request's own team | the request's team (managers of a team above it count, as today) |

Stored in the existing forms, extended:

- **Text settings** (`orders_buyers`, `orders_funding_managers`, `inventory_managers`): one row per line. `Badge > Team` / `Badge` as today; `Managers of Team M > Team T` / `Managers of Team M`; `Managers of each team` for the request's own team. The parser lives in Reach; unknown lines grant nothing.
- **Approval step approvers:** `approval_step_approvers` gains `kind` (`badge`, `team_managers`, `own_team_managers`; default `badge`) and `manager_team_id` (FK to teams, cascade); `badge_id` becomes nullable, with a validation per kind. Reversible migration; the uniqueness index covers the new columns.
- **Who can request** (`orders_requesters`) keeps its team list ("members of these teams") and gains badge and manager rows in the same line form. Blank still means everyone signed in.

`Reach#team_ids` stops adding managed teams by itself; only rows grant. Admins still reach everything. The requester still can't approve their own request.

### Defaults for a new site

- Who can request: everyone signed in.
- Who approves (first step): "Managers of each team".
- Who buys: nobody but admins until a row is added. Orders setup's Buyers box directions: "Add who buys, for example holders of a Buyer badge."
- Funding managers: admins only until a row is added.
- Inventory Managers: "Managers of each team" (inventory has no approving or buying to separate).

### Existing sites

A reversible data migration writes today's rules out as rows, so behavior doesn't change on upgrade: it appends `Managers of each team` to `orders_buyers`, `orders_funding_managers` and `inventory_managers` (creating the setting row when absent), and adds an `own_team_managers` approver row to every approval step. The admin then removes rows on Orders setup. Down removes exactly what up added.

### Screens

Orders setup's grant boxes (Who approves, Over $X also needs, Who buys, Funding managers) and Inventory setup's Inventory Managers draw each row as: a "Who" select (A badge / Managers of a team / Managers of the request's own team) that reveals the badge or team picker inline, then "For" (team picker, blank = every team; hidden for own team). "Any of these" above the list. Remove "Team managers can always ..." wording everywhere it appears (setup pages, setting hints, `orders-spec.md`, MCP descriptions).

## Tests

- Reach: each row kind; managed teams no longer reach without a row; admins always do; unknown lines grant nothing.
- Access: a manager without a row can't approve or buy; with "Managers of each team" they can for their team and the teams below; "Managers of Team M > every team" lets M's managers buy for every team; self-approval still refused.
- Migration up/down on a database with steps and settings.
- Setup screens save and redraw each row kind; opening and saving changes nothing.
- Inventory: managers of a team aren't inventory managers without a row.

## Fork notes

- `feature/orders` and `feature/inventory` only. MCP order tools (`feature/mcp-orders`) go through `Orders::Access` and need no change; check its tool descriptions for "team managers" wording.
- Update `orders-spec.md` §3.13/§4 role table and setup page section, and `inventory-spec.md`.
- HBR rollout: after upgrade nothing changes; to separate the roles remove "Managers of each team" from Who buys and add a Buyer badge row.
