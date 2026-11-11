# BL-041: A family member's credit counts toward a count item but isn't listed under Done

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | medium |
| Status | new |
| Added | 2026-11-11 |
| Commit checked | `hbr/integration` @ `f19a201d` (`v0.0.0-hbr.38`) |
| Planned branch | `feature/checklists-connectors` (fix on the branch itself) |
| Upstream issue / PR | none |

## Summary

A count item that's owed together through a relationship (**Owe together through**, e.g. guardianship) pools the group's credit. When a guardian works a shift, the student's count goes up, but the student's item detail doesn't list that shift under **Done**. The numbers and the list disagree, so the student or a mentor can't see where the credit came from. Found by the help site's capture work on the demo (hbr.38).

## Where things are (`f19a201d`)

- `app/models/checklists/kinds/count.rb:246-259`, `person_detail`: `progress.lines.flat_map(&:records).select { |record| record.person_id == person.id }` keeps only the person's own records. `progress` already includes the group's records; that's what the count uses.
- The same filter feeds `taken` (line 256), so a date a family member already holds is still offered under the chances to earn.

## Fix

- Keep every record in `progress`'s lines, not just the person's own. Label records earned by someone else with their name ("Shift on Mar 3, by Pat Lee"), so it's clear the credit was pooled. The viewer may already see the group's progress (the item's default read level is `group` when pooled), so naming the group member shows nothing new.
- Build `taken` from all of them too, so a date a family member holds isn't offered again.
- Unpooled items are unchanged: their lines only hold the person's records.

## Tests

- Pooled item: a guardian's confirmed check-in shows under the student's Done with the guardian's name, and the student's own records show without one.
- A date the guardian signed up for isn't offered to the student under chances.
- Unpooled item: Done lists only the person's records, as before.

## Fork strategy notes

Fork-only code (`feature/checklists-connectors`). Behaviour fix inside an existing feature; no flag.
