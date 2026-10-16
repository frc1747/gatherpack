# BL-009: Person#all_team_ids and #all_ancestor_team_ids don't return plain ids

| | |
|---|---|
| Kind | upstream bug (latent: no wrong behaviour in upstream today) |
| Priority | low |
| Status | waiting |
| Added | 2026-10-06 |
| Upstream checked | `upstream/main` at `32e8023` |
| Planned branch | none yet; a tiny `feature/person-team-ids` if we offer it upstream |
| Upstream issue / PR | none |

## Summary

`Person#all_team_ids` and `Person#all_ancestor_team_ids` are named as if they return team ids, but part of what they return is `Team` records. Every upstream caller passes the result straight into a query (`where(id: ...)`), where Rails treats records and ids the same, so upstream behaves correctly. Code that treats the result as ids (`include?(some_id)`, comparing with `team_id`) silently gets the wrong answer.

**Why it's our problem now:** it bit us first. On 2026-10-06 the form creator check on `feature/forms` used `person.all_ancestor_team_ids.include?(record.team_id)` and always got `false`, so no student leader could create a form. The new tests caught it before it shipped. `feature/forms` now uses `person.all_ancestor_teams.ids` (and `.where(id: ...).exists?`) instead. Until this is fixed, anything new we write has to avoid these two methods, or use them only inside a query.

## Evidence (`upstream/main` at `32e8023`, `app/models/person.rb`)

```ruby
def all_team_ids                                  # line 69
  direct_team_ids = teams.select(:id)             # a relation of Team records (id only)
  managed_team_ids = memberships.where(manager: true).select(:team_id)
  descendant_ids = Team.where(id: managed_team_ids).flat_map(&:all_descendants).map(&:id)
  ancestor_ids = Team.where(id: direct_team_ids).flat_map(&:all_ancestors).map(&:id)
  direct_team_ids + descendant_ids + ancestor_ids # Team records + strings
end

def all_ancestor_team_ids                         # line 81
  direct_team_ids = teams.select(:id)
  ancestor_ids = Team.where(id: direct_team_ids).flat_map(&:all_ancestors).map(&:id)
  direct_team_ids + ancestor_ids                  # Team records + strings
end
```

`teams.select(:id)` loads `Team` objects with only `id` set. `Relation + Array` converts the relation to an array of those objects and appends the ancestor id strings. So for a member of Den A under Pack under Org you get `[#<Team id: "den-a">, "pack", "org"]`.

The `teams.select(:id)` line dates from upstream `f2630b0` (2025-05-06). `all_ancestor_team_ids` was added in `3ee7705` (2025-08-01, "320 don't show child teams on manager's person page").

Callers (upstream and ours), all safe today because each one is inside a query:

- `app/models/person.rb`: `all_teams` (`Team.where(id: all_team_ids)`), `all_ancestor_teams`, and the current time clock periods (`where(team_id: all_team_ids)`)
- `app/policies/team_policy.rb:7`, `app/policies/membership_policy.rb:7`

## Proposed fix

Use `teams.ids` (plain id strings) instead of `teams.select(:id)` in both methods:

```ruby
direct_team_ids = teams.ids
```

Both methods then return arrays of id strings, and every existing caller keeps working, since `where(id: [...strings])` is what it was effectively doing. It costs one extra small query per call in the descendant/ancestor lookups (`Team.where(id: direct_team_ids)` now takes an array instead of a subquery). That's negligible next to the `all_descendants` / `all_ancestors` recursion that's already there.

Optionally `.uniq` the result, since a team can appear both directly and as an ancestor.

## Tests

In `test/models/person_test.rb` (upstream Minitest style): build Org → Pack → Den A, put a person in Den A, and assert `person.all_ancestor_team_ids` equals the three ids as strings, and that `all_team_ids` includes each with `include?`. Add a manager case for `all_team_ids` (managed team plus its descendants).

## Fork strategy notes

- Touches one upstream file (`app/models/person.rb`). Both person-fields and forms already modify `person.rb`, but in other methods, so a conflict is unlikely.
- Don't carry this as a fork-only branch. Our code already works around it, and a fork edit to `person.rb` for a cleanup isn't worth the merge cost. Either offer it upstream, or leave it and keep using `all_ancestor_teams.ids`.
- If offered upstream, frame it as "return what the name says", not as a user-facing bug.

## Draft upstream issue

> **`Person#all_team_ids` / `#all_ancestor_team_ids` return Team records mixed with ids**
>
> Both start from `teams.select(:id)`, which yields `Team` objects, then append id strings, so the result is `[#<Team id: ...>, "id", ...]`. Every current caller passes it to `where(id: ...)`, so nothing misbehaves today, but code that calls `include?` on it gets the wrong answer. Switching to `teams.ids` makes both return plain ids with no change for existing callers. Happy to send a PR with a test.
