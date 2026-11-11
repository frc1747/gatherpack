# BL-041: A family member's credit counts toward a count item but isn't listed under Done

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | medium |
| Status | started (`feature/checklists-connectors`, see `FORK.md`) |
| Added | 2026-11-11 |
| Commit checked | `hbr/integration` @ `f19a201d` (`v0.0.0-hbr.38`) |
| Planned branch | `feature/checklists-connectors` (fix on the branch itself) |
| Upstream issue / PR | none |

## Summary

A count item that's owed together through a relationship (**Owe together through**, e.g. guardianship) pools the group's credit. When a guardian works a shift, the student's count goes up, but the student's item detail doesn't list that shift under **Done**. The numbers and the list disagree, so the student or a mentor can't see where the credit came from. Found by the help site's capture work on the demo (hbr.38).

## Where things are (`f19a201d`)

- `app/models/checklists/kinds/count.rb:246-259`, `person_detail`: `progress.lines.flat_map(&:records).select { |record| record.person_id == person.id }` keeps only the person's own records. `progress` already includes the group's records; that's what the count uses.

## Fix (2026-11-11)

- `person_detail(item, person, viewer:)` keeps the group's records when the viewer sees the pooled group by name (spec §10.1: names show at the `group` level): admins, the person, anyone in or related to the person's group through the pooling relationship, and the person's leaders. Anyone else (a badge grant, a teammate) still sees only the person's own records, since the stored result never names group members.
- Records earned by someone other than the person end with "· by <name>".
- Still open is unchanged: it leaves out only dates the person holds, since a family member holding a date doesn't stop the person earning there too.

## Tests

`test/controllers/checklist_count_details_test.rb`: the person sees a parent's shift under Done with the parent's name; the parent sees it too; a teammate outside the group and a viewer-less call see only the person's own.

## Fork strategy notes

Fork-only code (`feature/checklists-connectors`). Behaviour fix inside an existing feature; no flag.
