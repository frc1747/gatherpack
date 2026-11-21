# BL-063: Home and My GatherPack screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | high |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/my-gatherpack`, `feature/my-gatherpack-family`, `feature/my-gatherpack-activity`, `feature/phone-notifications`, `feature/installable-app`; after BL-062 |
| Upstream issue / PR | none |

## Summary

Home is already the most consistent part of the app: every row is an `mg-row` with one solid action and the rest outline. What's left is the pages around it: the replaced Hours page has six footer buttons in five colours, the Activity page has a separate "Show" button for its filter, and the Family page's "See open shifts" sits apart from the other rows. Bring them to the standard without touching the Home rows. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Home `app/view_overrides/my_gatherpack/welcome/dashboard.html.erb` | header, columns of `mg-row` (`my_gatherpack/_todo_row.html.erb:13` first row solid, rest outline) | none: matches the "My GatherPack row" kind. Check each connector row (`orders/_my_gatherpack_orders.html.erb` "New request" `btn-primary`) uses `_todo_row` or the same classes |
| Hours `app/view_overrides/my_gatherpack/time_clock_punches/index.html.erb:34-44` | New Time Clock Punch (`btn-success`), Time Clock Periods (`btn-info`), Flag Review (`btn-warning`), Search, Clear Search, Time Clock Kiosk (`btn-warning`) | footer: New Time Clock Punch, Search, Clear Search (upstream's filter card); a **More** menu (`_action_row`) with Time Clock Periods, Flag Review, Time Clock Kiosk |
| Activity `my_gatherpack/activity/show.html.erb:14` | season select plus a "Show" `btn-primary` | `_filter_bar` with the season select submitting on change (keep a no-JS submit hidden with `d-none`); section links stay row buttons |
| Family `family/show.html.erb:19`, `family/_ward_card.html.erb` | ward cards; "See open shifts" full-width outline button at the bottom of one card | keep cards (they are My GatherPack rows); "See open shifts" becomes a row in the ward card's sign-up section, same `mg-row` shape |
| Share `share/show.html.erb` (`feature/installable-app`, the phone share target) | no breadcrumb; one card with the shared link or text and one large button per share action | breadcrumb `Home > Share` (it opens from the phone's share sheet, so the breadcrumb is the way back); keep one card with `btn-lg btn-primary` per action (public-page kind) |
| Notification settings `notification_settings/show.html.erb` | a person's own settings; "Send a test notification" outline | header card per standard; the test button becomes `btn-secondary` (full-size buttons are solid) |

## Works differently

Hours: Periods, Flag Review and Kiosk move into More. Note it in the HBR changelog.

## Tests

- Hours page footer shows New, Search, Clear Search and More; More holds the three links, each shown under the same condition as today.
- Activity: changing the season reloads with that season (system test), and the no-JS submit still works.
- Family page: "See open shifts" link present inside the ward card when sign-ups are on.
- Share page renders a breadcrumb back to Home, with and without share actions.
- Existing my-gatherpack tests stay green; none weakened.

## Fork notes

- No flag (rearranges the feature's own screens). No upstream files touched (the Hours page is already an override).
- Retake gphelp screenshots: Hours (desktop and phone), Activity, Family, Share.
