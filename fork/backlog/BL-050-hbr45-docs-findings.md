# BL-050: Problems found documenting hbr.43-45

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | high (1), medium (rest) |
| Status | open (waiting on the fork owner) |
| Added | 2026-11-17 |
| Commit checked | `v0.0.0-hbr.45` (demo) |
| Planned branch | `feature/orders`, `feature/inventory`, `feature/settings-inputs`, `feature/my-gatherpack-family`, `feature/my-gatherpack` / `feature/event-time-display`, search |
| Upstream issue / PR | none |

Reported by the help-guide session; the guides leave these out.

1. **Settings missing from the setup pages.** With Orders or Inventory on, the Settings page shows only a link to the feature's setup page (`Settings.page`), but those pages don't hold every setting: orders' price tolerance, funding managers, close-after days and others, and some inventory settings, can only be edited by turning the feature off. The setup controller comment says they "stay on the settings page". Fix: put every setting of the group on its setup page (or keep the unhandled ones on the Settings page).
2. **Inventory Managers picker wording.** The empty team choice says "Up to: their own teams", but an empty team means every team (`Inventory::Reach`).
3. **Funding source dates show a time** as well as the date.
4. **Search** for "Concessions" returned an announcement whose text doesn't contain the word.
5. **Family page:** an event starting at midnight shows "Time not set yet" (the BL-049 all-day handling doesn't reach it).
6. **Home Coming up** shows midnight-to-midnight events as "12:00 AM - 11:59 PM" (same cause; only My activity was fixed).
7. **Demo setting:** "Kiosk: Managers Clock Out the People They Manage" is on in the demo (default off), so the kiosk shows a Manager button. Unknown who changed it.
8. **Registrations in members' menu.** Members see Registrations under People; opening it (or hover prefetch) shows "You are not allowed to do that". Hidden where menu items take a visible check (feature/intake).
