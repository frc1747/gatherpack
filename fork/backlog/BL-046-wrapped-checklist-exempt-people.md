# BL-046: Checklists made from commitments treat an exempt badge as "not on the checklist"

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | medium |
| Status | blocked (on the decisions below) |
| Added | 2026-11-15 |
| Commit checked | `feature/checklists-connectors` (as merged in `hbr/integration` @ `2d28c89f`, `v0.0.0-hbr.40`) |
| Planned branches | `feature/checklists-connectors` (wrapping, visibility); `feature/checklists` (evaluator, if decision 2 changes the overall) |
| Upstream issue / PR | none |

## Summary

`Checklists::WrapCommitments` turned each commitment into a checklist. A commitment's **exempt badge** ("doesn't owe") became a checklist-level **exclude** rule ("isn't on the checklist at all"). On production that affects one checklist, Outreach 2026–27: include "Team 1747 - Students" and the teams below it, exclude the "2027 Season Rookie" badge. 49 people are in the team, 19 are rookies, and 30 are covered.

A rookie is welcome at Outreach but can't open the checklist (404) or see their outreach there. Their Travel Eligibility checklist even shows the Outreach line as "Rookie / Not counted".

## Where things are

- `app/models/checklists/wrap_commitments.rb:90-99` (`rules_for`): `add_rule(checklist, :exclude, :badge, badge_id: commitment.exempt_badge_id)` with no `item_id`.
- `app/models/checklists/wrapped_visibility.rb`: who sees a wrapped item and its checklist's overall is the commitment's reach (`Checklists::Kinds::Count.commitment_reach`), which goes through `Commitment#owing_people` and so leaves exempt badge holders out (`app/models/commitment.rb:185-190`).
- `app/models/checklists/evaluator.rb:119`: people an item doesn't apply to get a bare `Result.exempt(label)`, with no measures.
- `:140-148` (`overall`): exempt results are ignored, so a checklist whose only items are exempt is **met** (checklists spec §3, "Overall").

## What a data-only fix gives (probed on prod, rolled back, 2026-11-15)

Moving the exclude rule onto the count item puts a rookie on the checklist, but:
- the overall reads met ("Complete") with zero events;
- the item shows "Doesn't owe" with no count;
- the person still can't open it, because visibility goes through the commitment.

## Fix

1. Wrapping maps an exempt badge to an item-level exclude rule. A data migration moves the rule on already-wrapped checklists.
2. A person a checklist covers always sees their own row, on wrapped checklists too.
3. Exempt count items still show the person's tally ("Doesn't owe · 2 events"). Showing someone their own numbers leaks nothing.

## Decisions needed (Corey)

1. Are rookies on Outreach 2026–27 as "doesn't owe", or not on it at all? If not on it, only [BL-045](BL-045-checklist-rule-wording.md)'s leak rule is needed, and [BL-044](BL-044-home-my-season-and-activity.md)'s activity page shows their outreach.
2. Should a checklist where every counting item is exempt read "Complete" (the spec today) or "Not counted"? Sign-up rules accept exempt either way.

## Tests

Wrapping a commitment with an exempt badge makes an item-level rule. An exempt person opens the checklist and sees their tally. Whatever decision 2 settles is pinned in the evaluator tests.

## Fork strategy notes

Fork-only. The behaviour change is inside the flagged checklists feature. Update checklists spec §3 if decision 2 changes the overall.
