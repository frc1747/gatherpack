# BL-055: Pinned Save/Cancel on every form, not just Order Settings

| | |
|---|---|
| Kind | fork-only (UX) |
| Priority | medium |
| Status | shipped hbr.51 |
| Added | 2026-11-18; revised 2026-11-18 (owner: make the pinned bar the standard everywhere instead of removing it) |
| Commit checked | `hbr/integration` @ `b251e91d3` (hbr.50) |
| Planned branches | new `feature/pinned-form-buttons` (from `upstream/main`); `feature/orders` and `feature/inventory` (their own bars) |
| Upstream issue / PR | none |

## Summary

Order Settings and Record delivery keep Save and Cancel in a bar pinned to the bottom of the window. Every other form ends with ordinary buttons, so on a long form you scroll to the end to save. The fix is to make pinned buttons **the standard on every form**, not to remove them from Orders.

## Evidence

- 204 views have a submit button. 138 put it in a `card-footer` (upstream's pattern, e.g. `app/views/settings/index.html.erb:43-48`). Others use `.actions`, `d-flex gap-2`, `col-auto` or `modal-footer`.
- Orders' and Inventory's bars: `app/views/orders/settings/show.html.erb:64`, `app/views/orders/deliveries/new.html.erb:46` (`fixed-bottom`, a spacer, Save stretched full width).

## Design

- **Sticky, not fixed.** A form's button row uses `position: sticky; bottom: 0`. While the form runs past the bottom of the window, the buttons stay in view at the bottom edge. Once the form's end scrolls into view, they sit in their usual place at the end of the form. Short forms look exactly as they do now. Nothing is hidden behind the bar, so no spacer is needed.
- **Look:** the row keeps its own buttons, order and sizes, so upstream's "Save, then Cancel" stays. It gets the page background, a top border and a small shadow, so it reads as a bar over the fields scrolling behind it. On phones it sits above the bottom tab bar where one is shown.
- **Which rows:** a form's `card-footer` that holds a submit button, plus the other endings found in the survey (`.actions` and the `d-flex gap-2` endings) that end a form with a submit. This is done in CSS (`:has()`), so no upstream view changes. Modal footers, search and filter bars, inline one-field forms and kiosk screens are left alone. Fork views that need it add the class `gp-form-actions`.
- **Orders and Inventory:** Order Settings and Record delivery drop their own `fixed-bottom` bar and spacer and use the standard: a card footer with Save first, at natural width. The single-action bars ("Mark all received" on a request, unit actions, machine actions) stay as they are: they're one tap at the foot of a long list, not a form's Save.
- **Flag** `feature_pinned_form_buttons` ("Pinned form buttons"), off by default (AGENT.md rule 10). With the flag off, nothing changes. Orders and Inventory then use their card footers unpinned.

## Tests

- System test: on a long form (Setup) at phone and desktop sizes, the Save button is in the viewport before scrolling with the flag on, and not with it off. A short form looks unchanged.
- The flag's stylesheet is present only when the flag is on.
- Orders/Inventory: tests that found buttons in `.fixed-bottom` are updated, and Save and Cancel still work.

## Fork notes

- `feature/pinned-form-buttons`: one line in `app/views/layouts/application.html.erb` that renders the flag's stylesheet. Placed away from smooth-pages' head line, checked by a trial merge into integration. Recorded in FORK.md "Upstream files touched".
- The Orders and Inventory view changes are made after tasks 331-333 merge, because they edit the same settings view.
- Recapture gphelp screenshots of long forms once HBR turns the flag on.
