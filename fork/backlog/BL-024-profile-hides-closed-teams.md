# BL-024: Profiles hide the closed teams a person is in

| | |
|---|---|
| Kind | upstream feature |
| Priority | low |
| Status | waiting |
| Added | 2026-10-13 |
| Upstream commit checked | `86ab397` (`upstream/main`) |
| Planned branch | `feature/profile-all-teams` (from `upstream/main`) |
| Upstream issue / PR | none |

## Summary

A non-admin who opens another member's profile sees only some of that member's teams: the ones the viewer belongs to, plus teams anyone can join. Closed teams the viewer isn't in (join permission `added_by_admin`, `added_by_manager` or `added_by_current_member`) are left off the profile. Example: a student opens another member's profile and sees "Class of 2027" and "Team Leadership", but none of their subteams.

This is upstream behavior, not something the fork added. Checked 2026-10-13: none of our feature branches change `TeamPolicy::Scope` or the Teams section of the profile.

Decided with Corey (2026-10-13): we can explain this and it isn't urgent. Park it.

## Why it happens

- `PeopleController#show` builds the profile's team list with `policy_scope(@person.all_ancestor_teams)` (`app/controllers/people_controller.rb:13` at `86ab397`).
- `TeamPolicy::Scope#resolve` (`app/policies/team_policy.rb:3-11` at `86ab397`) gives non-admins `person.all_team_ids` (own teams, their parents, and children of teams they manage), plus teams with `has_account` or `requires_approval`. The scope dates from `9a156e3` (2024-06); the joinable-team part came in `9a4e0c9` (2026-07, "people can ask to join teams now").
- The scope was written for team discovery (the Teams list, search, filter dropdowns), so you see your own teams and the ones you can join. The profile reuses it, so hiding teams there is a side effect, not a privacy rule.

## Why it's low harm to change

- The hiding doesn't protect much. `ApplicationPolicy#show?` is `true`, so anyone can open a closed team's public page (`TeamsController#show` renders `show_public` for non-members). Only the full page with the member list is restricted (`TeamPolicy#show_full?`, `app/policies/team_policy.rb:33`).
- Members can already browse the whole directory. The only thing hidden is which closed teams each person is in.
- One thing to check first: a closed team whose *name* is sensitive (medical, financial aid, discipline). Look at prod team names (names only, nothing else) before shipping. If there are any, see the alternative below.

## Workaround we're not using

Changing a team's join permission to `has_account` or `requires_approval` makes it show on profiles, but that setting decides who can join. `has_account` lets any member add themselves. Don't use join permissions to control visibility.

## Proposed fix

Change only the profile. Leave `TeamPolicy::Scope` alone: search (`search_controller.rb:43`), the index filters (`announcements`, `calendar`, `events`, `time_clock_periods`) and `MembershipsController#set_team` (`memberships_controller.rb:99`) all depend on it, and they should keep showing only the teams you can see or join.

- In `PeopleController#show`, list all of `@person.all_ancestor_teams` for anyone who can view the person, without `policy_scope`. Badge links still go to `teams#show`, which already falls back to `show_public`.
- Alternative, if some team names must stay hidden: add a team-level "Show on profiles" setting (new column on `teams`, default on) and filter on it there. This is bigger. Only do it if the prod check turns up such a team.

## Tests

- A member who isn't in a closed team sees it on another member's profile, and the badge opens its public page, not the member list.
- The Teams list, search and filter dropdowns still leave out closed teams the viewer isn't in.
- Admin view is unchanged.

## Fork strategy notes

Touches upstream files (`app/controllers/people_controller.rb`, and its test), so it's an upstream-shaped branch from `upstream/main` with no `Hbr` naming. `feature/person-fields` also edits `people_controller.rb` (create/update/params), not `show`, so a conflict is unlikely. It's a small, generic change. Confirm with Corey before opening an issue upstream. Related: [BL-009](BL-009-person-team-ids-return-records.md) (`Person#all_team_ids` return values).
