# BL-097: Some MCP tools look up a person outside what the member can see

| | |
|---|---|
| Kind | fork bug (security, `feature/mcp-*`) |
| Priority | high |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | fix on `feature/mcp-checklists-intake`, `feature/mcp-commitments`, `feature/mcp` |
| Upstream issue / PR | none yet |

## Summary

Most MCP tools find records through `ctx.find` / `ctx.policy_scope`. A few take a `person_id` through the unscoped `Mcp.find_by_neat_id` and only then check the parent record, so a member can ask about a person they can't see: `checklist_status` returns that person's status on a visible checklist, `commitment_progress` returns their progress, and the error text tells a real id from a fake one. `add_token` says whether a card value is used by anyone at all; `find_duplicate_people` confirms emails; `get_person` returns `bio` always and relationships through a scope wider than the profile page.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/models/mcp/tools/checklist_status.rb:23`, `:35-39` (`one_checklist` skips `policy_scope(Person)`; `all_checklists` applies it).
- `app/models/mcp/tools/commitment_progress.rb:105`, `:142-149`.
- `app/models/mcp/tools/add_token.rb:22` (global `Token.exists?`).
- `app/models/mcp/tools/find_duplicate_people.rb`, `get_person.rb:35-60`.
- Seam: `app/models/mcp/context.rb:50-95`.

## Proposed fix

1. Every `person_id` goes through `ctx.find(ctx.policy_scope(Person), id)`; unknown and not-visible give the same "Not found".
2. `add_token`: report "already in use" only when the existing token belongs to someone the member can see; otherwise a generic refusal.
3. `get_person`: `bio` and relationships follow the same field rules and relationship scope as the profile page.
4. A tool spec helper that runs each tool with a stranger's id and expects "Not found".

## Tests

- For each tool taking `person_id`: as a member, a stranger's id and a fake id both give the same "Not found".
- `get_person` fields match what the profile page shows that viewer (teammate, guardian, manager).
- Ditto first: `checklist_status` with a stranger's id as the student.

## Fork strategy notes

Fork-only; each tool's fix goes on the branch that added it.
