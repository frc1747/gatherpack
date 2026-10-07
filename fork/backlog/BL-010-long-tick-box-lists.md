# BL-010: Keep long tick-box lists short on the printable list

| | |
|---|---|
| Kind | fork-only (part of `feature/forms`, which isn't proposed upstream) |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-07 |
| Planned branch | `feature/forms` (no new branch; it's the same feature) |
| Upstream issue / PR | none |

## Summary

Spec rev. 8 (`d8166af` on `feature/forms`) replaced the printable list's multi-select boxes with tick boxes: the Columns (form questions and profile details) and the answers under "People who answered a question". Tick boxes are easier than multi-select boxes, but they grow one row per item. As forms and custom profile fields grow, the page will scroll on and on.

Size today: on Ditto (a copy of production, 2026-10-07) the Meal Choices form has 12 questions you can pick people by and the Travel Requirement Acknowledgement has 9. Production has 7 custom profile fields plus the built-in ones. That's manageable now, not later.

Corey asked (2026-10-07) for something "as easy as a checkbox, but doesn't scroll on forever".

## Proposed fix

One small reusable partial (plus a Stimulus controller) for a list of tick boxes, used for Columns → Answers, Columns → Profile details, and a question's answers:

1. **Columns.** Lay the tick boxes out in two or three CSS columns on wide screens and one on phones.
2. **Show all.** Past about 8 items, show the ticked ones plus the first few, with a "Show all N" link that opens the rest in place. Short lists look exactly as they do now.
3. **Groups.** Profile details get a small heading per person field group. Form questions could use the form's own heading questions the same way.
4. **Find box, later.** Add a "Find…" box that filters the list as you type only once a list is long enough to need it (about 12 or more items).

## Tests

- A controller test that a long list renders every tick box (hidden ones included, so they still submit when ticked) and that ticked items are always visible.
- Short lists render no "Show all" link.
- Check in a browser at phone width that there's no sideways scrolling.

## Fork strategy notes

All of this lives in new files on `feature/forms` (a partial, a Stimulus controller, maybe a few CSS rules in a forms stylesheet). No upstream files change.
