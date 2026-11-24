# BL-083: More menus are too cramped to tap on a phone

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | open |
| Added | 2026-11-22 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | `feature/screen-kit` |
| Upstream issue / PR | none |

## Summary

On a phone, the **More** menu is where most of a page's actions end up (the action row keeps only its first button). Its items are packed tightly, so it's easy to tap the wrong one, and Delete sits right under Archive. Give menu items phone-sized spacing.

## Evidence

- `app/views/shared/_action_row.html.erb:25-34`: More is a plain Bootstrap `dropdown-menu`; each item is `dropdown-item` (`app/helpers/screen_kit_helper.rb:30-32`), with Bootstrap's default padding of 0.25rem by 1rem. That makes rows about 32px tall, under the 44px minimum touch target in Apple's and Google's guidelines (and WCAG 2.5.5's 44px).
- `app/assets/stylesheets/screen_kit.css` has no rule for menu items. It loads only with `feature_screen_standard` (`app/views/layouts/_screen_kit.html.erb`), which is on in production.
- The same cramped items are in every other dropdown: Columns, filter funnels, checklist **Add item**, list-page menus (39 views use `dropdown-menu`).

## What it does

On touch screens, every dropdown menu item is at least 44px tall:

- `screen_kit.css`, inside `@media (pointer: coarse)`: `.dropdown-menu .dropdown-item { padding-block: .75rem; min-height: 44px; display: flex; align-items: center; }`, and a little more space around `.dropdown-divider`.
- Destructive items (Delete, in red) get a divider above them in More, so the last, dangerous item is set apart. `_action_row` adds `<li><hr class="dropdown-divider"></li>` before the first destructive item when there are other items above it.
- `pointer: coarse` rather than a width breakpoint: a narrow desktop window keeps compact menus, and a tablet gets the roomy ones.

Decisions:
- **All dropdowns, not just More.** One menu style everywhere, so the fix lives once in the screen kit's CSS, not per menu.
- **No setting.** Bigger tap targets on touch screens suit every group.
- **Under `feature_screen_standard`,** like the rest of the kit's styles.

## Tests

- System test at phone size with touch emulation (or a CSS test reading the computed style): a More item's height is at least 44px; at desktop with a mouse it's unchanged.
- `_action_row` with Archive and Delete renders a divider before Delete; with only Delete in More, no divider.

## Fork notes

Fork-only: `feature/screen-kit`'s stylesheet and partial. No upstream files.
