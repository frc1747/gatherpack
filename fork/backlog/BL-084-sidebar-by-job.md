# BL-084: The sidebar is sorted by feature, not by job, and report Pages are buried

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | shipped hbr.53 |
| Added | 2026-11-23 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | `feature/my-gatherpack` |
| Upstream issue / PR | none |

## Summary

The My GatherPack sidebar puts each item where its feature registered it, so related jobs are scattered. Forms and Sign-ups are in the top group, but Checklists drops into a leftover "People" heading further down. Pages is where managers go to pull reports, and it is 10th of 11 in the flat Manage list. Members get a short menu, which is right. Managers, though, lose the things they use every day. This item regroups the menu by job and lifts report Pages to the top. It also lets each person pin what they use most, so one group's habits don't set the order for everyone.

## Evidence

- Production, Ditto and Demo run My GatherPack (`STATE.md`), so the sidebar is the view override `app/view_overrides/my_gatherpack/layouts/_sidebar.html.erb`, built by `MyGatherpack::Menu` (`app/models/my_gatherpack/menu.rb`).
- Placement table, `config/initializers/my_gatherpack.rb:32-49`:
  - Top group: Forms 10, Sign-ups 20, My Hours 30, Calendar 40, Teams 50, Announcements 60.
  - Manage: People, Teams, Time Clock, Badges, Tokens, Commitments, Ledgers, Budgets, Mailboxes, **Pages (100)**, Widgets.
- Nothing places Checklists, Registrations or Shortcuts. `Menu#sections` (`menu.rb:60-67`) shows those under their feature's section heading after the Family group. That is why Checklists sits apart from Forms and Sign-ups.
- Manage is one flat list with no headings (`menu.rb:69-79`). Nothing collapses, and there is no per-person order or pinning anywhere in the sidebar.
- `pages` has no column saying a page belongs in the menu (`db/schema.rb`, `create_table "pages"`). The only way to reach a report Page is Manage → Pages → find it in the list.

## What it does

1. **One "Sign-ups & forms" run in the top group:** Sign-ups, Forms, Checklists, next to each other in that order. Registrations, for those who can see it, goes in the Manage group's People part (below), not in a leftover section.
2. **Report Pages in the menu.** The Page edit page gets a **Show in the menu** tick box. Ticked Pages appear as their own group right under the top group, headed **Reports**, sorted by title. Each person sees only the Pages their Viewer level lets them open (`PagePolicy::Scope`), so a member sees only the member-level ones and the group disappears when there are none. The group ends with an **All pages** link for anyone who can see the Pages list. In Manage, Pages is the first item of the Content part.
3. **Manage gets short headed parts**, in this order:
   - **People:** People, Teams, Badges, Tokens, Commitments, Registrations.
   - **Time:** Time Clock.
   - **Money:** Ledgers, Budgets.
   - **Content:** Pages, Widgets, Mailboxes, Shortcuts.

   Each part folds open or shut from its heading, and the menu remembers which parts each person folded.
4. **Pin to the top.** Hovering over any sidebar item shows a pin. On a phone, the menu offers **Edit menu**, which shows the pins. A pinned item appears in a **Pinned** group above Home's group, in the order pinned. The item also stays where it was, so the menu shape never changes under someone. Pins are saved per person, so they follow them from laptop to phone. Clicking the pin again unpins the item.

Decisions:

- **Group by job, keep the member view short.** Members still see only the top group, Reports (if any are theirs) and Family. The regrouping, the parts and the pins help managers without adding anything for members.
- **"Show in the menu" is on the Page, not a separate list.** The Page is the thing the choice is about. Shortcuts stay what they are (links on Home).
- **Pins are stored on the server, not in the browser.** Columns choices live in `localStorage`, but a pin made on a laptop should be there on a phone. A small `menu_pins` table holds `user_id`, `path_key` (the nav item's path helper, or `page:<id>` for a report Page) and `position`. Deleting a Page removes its pins.
- **Group headings are plain, general words** (Pinned, Reports, People, Time, Money, Content), set in code like the menu's other labels. No setting: they suit any group, and `feature/my-gatherpack` has no settings of its own to hang one on.
- **Folding only in Manage.** The top groups stay open; folding them would hide the member's main jobs.
- **Under `feature_my_gatherpack`.** The classic sidebar is untouched.

## Tests

- `MyGatherpack::Menu` with Checklists, Forms and Sign-ups on: top-group order is Home, Sign-ups, Forms, Checklists, …, and Checklists no longer appears in a leftover section.
- Reports group: a member sees only member-level ticked Pages; a manager also sees manager-level ones; no ticked Pages means no Reports heading. An unticked Page never appears.
- Manage parts render in order with their headings; a part with nothing visible for this person is dropped.
- Pins: pinning adds the item to Pinned and leaves it in place; pins come back after signing in on another session; unpinning removes it; deleting a pinned Page removes the pin; a pin to an item the person can no longer see is not shown.
- System test: fold the People part, reload, still folded.

## Fork notes

Fork-only, all inside `feature/my-gatherpack`. That means the placement table and `Menu`, the override sidebar, a fork migration adding `pages.show_in_menu` (boolean, default false) and `menu_pins`, and a tick box on the Page form. The Page form is an upstream view, so record it in `FORK.md` "Upstream files touched", or add it through a form slot if one exists. Update gp-map's sidebar line at the same time: it is missing the My GatherPack override, `SidebarSlots` and `NavItem#visible?`.
