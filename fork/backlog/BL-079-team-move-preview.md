# BL-079: Moving people to another team fails at the preview

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | high |
| Status | shipped hbr.53 |
| Added | 2026-11-22 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | `feature/housekeeping` |
| Upstream issue / PR | none |

## Summary

On a team's **Move people** page, choosing people and a team and pressing the preview button stops with the browser error "Form responses must redirect". Nobody can move people between teams. It's the same in hbr.51; the help site found it while re-capturing for hbr.52, and production runs it.

## Evidence

- `app/views/team_moves/new.html.erb:15`: `form_with url: preview_team_move_people_path(@team), method: :post, data: { controller: "select-all" }`. It's a Turbo form. The Find form on the same page (line 6) has `data: { turbo: false }`.
- `app/controllers/team_moves_controller.rb:23-26`: `preview` renders `preview.html.erb` with 200. Turbo refuses a 200 page as the answer to a form submission.
- Came in with `27de0ff74` ("Archive, copy forward and clear old records by date"). `7007fa59e` (screen standard, hbr.52) only restyled the page.
- `app/views/housekeeping/index.html.erb:26` posts to `housekeeping#preview` the same way.

## Fix

Add `turbo: false` to the preview form's `data`, so the preview is an ordinary page load. `create` already redirects with 303. Check the Housekeeping preview form and give it the same fix if it fails the same way.

## Tests

- Integration: post to `preview_team_move_people_path` with `ids` and `to_team_id`; 200 and the preview lists the people.
- The `new` page's preview form carries `data-turbo="false"` (and the Housekeeping one, if changed).
- System: choose two people and a team, preview, confirm; both end up on the new team.

## Fork notes

Fork-only (`feature/housekeeping`). No upstream files.
