# BL-085: "See all your activity" looks like part of Your orders on Home

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | open |
| Added | 2026-11-23 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | `feature/my-gatherpack-activity`, `feature/my-gatherpack-orders` |
| Upstream issue / PR | none |

## Summary

On Home's side column, someone with no open order requests and nothing under My Season sees this:

- a **Your orders** heading with only a green **New request** button under it;
- right below that, an outlined **See all your activity** button with no heading of its own.

The activity button reads as an orders action, and the orders block gives no words about what's there.

## Evidence

- `config/initializers/my-gatherpack-activity.rb:32`: the activity section sits at side position 20.5 so that it shows "right under the checklists' My Season section (20), as its footer". The button was designed with My Season above it.
- `app/views/my_gatherpack/_checklists_season.html.erb:3`: My Season renders nothing when the person has no season rows.
- `app/views/my_gatherpack/_activity_season.html.erb:5-13`: the "Also this season" heading shows only when there are uncounted rows. Otherwise the section is the bare button.
- `config/initializers/my-gatherpack-orders.rb:8`: Your orders is side position 10. With My Season empty, the bare activity button lands directly under it.
- `app/views/orders/_my_gatherpack_orders.html.erb:9-26`: with no active requests, the block is the heading and New request, with no line saying there are none.

## Fix

1. **The activity section always has a heading.** It keeps **Also this season** when there are uncounted rows. Otherwise it gets **Your activity**, followed by one line, "Your check-ins, hours, sign-ups and forms this season.", and then the button. When My Season is shown right above it, the section still sits directly under it, as now.
2. **Your orders says when there's nothing open.** With no active requests, a line "No open requests." (the screen kit's empty-state style) goes above New request, with **My requests** beside it for past ones.

Decisions:
- **A heading in every case, rather than detecting whether My Season rendered.** The section can't see its neighbours, and a heading reads right under any section above it.
- **No new settings.**

## Tests

- Home with Orders on (requester, no requests) and the activity page on, and no season rows. "See all your activity" sits under a **Your activity** heading. **Your orders** shows "No open requests." and New request.
- With uncounted activity rows, the heading is **Also this season**, as now.
- A requester with active requests sees no "No open requests." line.

## Fork notes

Fork-only views in `feature/my-gatherpack-activity` and `feature/my-gatherpack-orders`. No upstream files.
