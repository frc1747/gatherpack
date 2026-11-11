# BL-042: Deleting a relationship type that a count item pools through breaks the item

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | low |
| Status | new |
| Added | 2026-11-11 |
| Commit checked | `hbr/integration` @ `f19a201d` (`v0.0.0-hbr.38`) |
| Planned branch | `feature/checklists-connectors` (fix on the branch itself) |
| Upstream issue / PR | none |

## Summary

A checklist count item can name a relationship type under **Owe together through**. Nothing stops an admin deleting that type: the delete succeeds, and the item then fails validation with *That relationship type no longer exists* until someone edits it. The help site's admin guide works around it by telling admins to change the item first. Found in the help site's code review (hbr.38).

## Where things are (`f19a201d`)

- `app/models/checklists/kinds/count.rb:94-96`: the validation that reports the missing type, after the fact.
- The type's id lives only in the item's JSON `config["group_relationship_type_id"]`, so no foreign key protects it. (`commitments.group_relationship_type_id` has one, but count items don't rely on that column.)
- `app/models/relationship_type.rb`: `has_many :relationships`, no destroy guard.
- `config/initializers/checklists_count.rb`, `to_prepare` block: where the count kind already adds associations to other models.

## Fix

Refuse the delete, naming what uses the type. In the `to_prepare` block, add a `before_destroy` on `RelationshipType` (through a small concern, like `Checklists::CountWatched`) that finds count items with `config ->> 'group_relationship_type_id' = id`, adds "Used by the checklist count item <item> in <checklist>" errors and `throw(:abort)`. `feature/blocked-delete-message` (BL-019) already turns the resulting `RecordNotDestroyed` into a message showing those errors.

## Tests

- Deleting a type that a count item pools through is refused, the type stays, and the alert names the checklist.
- Deleting a type no count item uses still works.

## Fork strategy notes

Fork-only code (`feature/checklists-connectors`); adds a seam-style concern, no upstream file edits. When fixed, the help site's `admin/badges-and-relationships` guide can drop its workaround.
