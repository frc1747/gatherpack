# BL-001: Page list ignores the Viewer setting and leaks content previews

| | |
|---|---|
| Kind | upstream bug (security) |
| Priority | high |
| Status | waiting (parked so Brad can work through our open PRs first) |
| Added | 2026-10-03 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/page-index-permissions` |
| Upstream issue / PR | none yet |

## Summary

The Pages list (`/pages`) and an individual page (`/pages/:id`) use different permission rules. Opening a page checks its **Viewer** setting. The list doesn't: it includes every page attached to any team the person belongs to, including parent and child teams. People see pages they can't open; clicking one gives "permission denied".

That's not just clutter. For normal Markdown pages, the list card shows the first 50 characters of the page content, so a restricted page leaks its title and opening text to everyone on the team. Dynamic (ERB) pages are safe, because the list only shows a "DYNAMIC" badge for those.

## How we found it

Corey noticed that pages "just show up, regardless of access" while building the team roster page (a dynamic page, kept at `~/dev/gatherpack/pages/team-roster.html.erb` in the workspace). Production had a dynamic page, "Roster Test", with Viewer `manager`. At HBR every member is in a sub-team of the top-level "FIRST Team 1747, Harrison Boiler Robotics" team, and `Person#all_teams` includes ancestor teams. So any page attached to that team shows up in every member's list.

## The code (upstream `32e8023`)

`app/policies/page_policy.rb`

```ruby
class Scope < ApplicationPolicy::Scope
  def resolve
    return scope.where(viewer: "public") unless user.present?
    if user.admin
      scope.all
    else
      scope.where(team: person.all_teams).or(scope.where(team_id: "")).or(scope.where(viewer: "public")).or(scope.where(viewer: "user"))   # line 8
    end
  end
end

def show?
  return true if user.present? && user.admin
  case record.viewer
  when "public"  then true
  when "user"    then user.present?
  when "team"    then record.team ? person.all_teams.include?(record.team) : user.admin
  when "manager" then record.team ? record.team.manager?(person) : user.admin
  when "admin"   then user.admin
  else user.admin
  end
end
```

Problems on line 8:

1. `scope.where(team: person.all_teams)` doesn't look at `viewer`, so `manager` and `admin` pages attached to any of your teams are listed.
2. `scope.where(team_id: "")`: Rails casts `""` to `nil` for the uuid column and generates `"pages"."team_id" = NULL`, which never matches anything (checked with `Page.where(team_id: "").to_sql`). It's dead code; it was probably meant to be `team_id: nil`, which would be wrong too (team-less pages with Viewer `team` are admin-only per `show?`).

The leak is in `app/views/pages/_page.html.erb` line 9, which every card in `app/views/pages/index.html.erb` (line 43) renders:

```erb
<%= strip_tags(format_page_content(page)).truncate(50, separator: " ") rescue "ERROR" %>
```

## Reproduce

1. As an admin, create a team T with a member M who isn't a manager.
2. Create a Markdown page attached to T, Viewer `manager`, content "Secret: the budget is ...".
3. Sign in as M and open `/pages`. The page is listed and its card shows "Secret: the budget is ...". Clicking it gives permission denied.

The same happens with Viewer `admin`, and with a page attached to a *parent* team of T.

## Proposed fix

Make the scope apply the same rules as `show?`, one Viewer level at a time:

```ruby
def resolve
  return scope.where(viewer: "public") unless user.present?
  return scope.all if user.admin

  scope.where(viewer: %w[ public user ])
    .or(scope.where(viewer: "team", team_id: person.all_team_ids))
    .or(scope.where(viewer: "manager", team_id: person.all_managed_teams.select(:id)))
end
```

Check the following before relying on it:

- **Manager equivalence.** `show?` uses `record.team.manager?(person)`, which is true for managers of the page's team *or any ancestor team* (`Team#all_managers_and_admins`). `Person#all_managed_teams` is the managed teams plus their descendants. Those should be the same set. Prove it with a test that covers a manager of a parent team.
- **`all_team_ids`** returns a mix of relations and arrays (`direct_team_ids + descendant_ids + ancestor_ids`). Check that it works inside `where(team_id: ...)`, or use `person.all_teams.select(:id)`.
- **Show becomes 404 instead of 403.** `PagesController#set_page` does `authorize policy_scope(Page).find(params[:id])`, so once the scope is tight, a page you can't see is "not found" rather than "not allowed". That's arguably better, since it doesn't confirm the page exists. Mention it in the PR so Brad can choose.
- Optional hardening: skip the content preview on the index for pages whose Viewer is above `user`, so a future scope bug can't leak text again. Only do this if Brad wants it; the scope fix alone closes the hole.

## Tests to write

`test/policies/page_policy_test.rb` is an empty stub upstream (no tests), so this branch adds the first ones. Follow the style of `test/policies/membership_policy_test.rb` from `feature/membership-create-policy`.

For each Viewer level (`public`, `user`, `team`, `manager`, `admin`), check that `Scope#resolve` includes exactly the pages `show?` allows, for:

- a signed-out visitor
- a plain member of the page's team
- a member of a child team (ancestor pages show up via `all_teams`)
- a manager of the page's team
- a manager of a parent team
- someone in no related team
- an admin

The cleanest form is one test that loops over all pages and all people and asserts `scope.include?(page) == policy.show?`, plus a few named cases for readability. Add a controller test that `/pages` doesn't render a restricted page's title or preview for a plain member.

## Fork-strategy notes

- Branch `feature/page-index-permissions` from `upstream/main`. It's a self-contained upstream bug fix, so no `Hbr` namespace and no feature flag.
- Upstream files touched: `app/policies/page_policy.rb`, `test/policies/page_policy_test.rb`, and `test/controllers/pages_controller_test.rb` (also an empty stub upstream).
- **Overlap with manifest branches:** none touch `page_policy.rb`, `pages_controller.rb`, or `app/views/pages/` as of 2026-10-03. `feature/enforce-authorization` (PR #518) explicitly doesn't cover `PagesController`, so it doesn't overlap.
- Upstream: report it under the umbrella issue [#517](https://github.com/GatherPack/gatherpack/issues/517) like the other fixes, or as its own issue since it's a data exposure. Confirm the branch and wording with Corey before opening anything; drafts are public.
- Add a `FORK.md` row when the branch is created, and add it to `fork/features.txt` once it's tested.

## Draft upstream issue text

> **Pages index lists pages the viewer can't open, and shows their content preview**
>
> `PagePolicy::Scope#resolve` includes every page attached to any of the user's teams (`person.all_teams`, which includes ancestor teams) without checking the page's `viewer` level, while `PagePolicy#show?` does check it. As a result, `/pages` lists `manager`- and `admin`-level pages to ordinary team members. For non-dynamic pages the index card shows the first 50 characters of the content, so restricted text is exposed even though opening the page is denied.
>
> Also, `scope.where(team_id: "")` compiles to `team_id = NULL` and never matches.
>
> Proposed fix: build the scope per viewer level so it matches `show?`, with policy tests asserting that the scope and `show?` agree for every viewer level and role.
