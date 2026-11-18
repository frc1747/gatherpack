# BL-055: Order Settings Save/Cancel are pinned to the bottom of the screen, unlike every other form

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | low |
| Status | waiting |
| Added | 2026-11-18 |
| Commit checked | `upstream/main` @ `eeaa691aa`; `feature/orders` @ `92bc6a174` |
| Planned branch | `feature/orders` |
| Upstream issue / PR | none |

## Summary

On Order Settings, Cancel and Save sit in a bar fixed to the bottom of the window, with Save stretched across the whole width. No other settings page or form in GatherPack does this: they end with ordinary Save and Cancel buttons at the bottom of the form. The Record delivery form has the same pinned bar.

## Evidence

- `app/views/orders/settings/show.html.erb:63-67`: `<div class="fixed-bottom bg-body border-top p-2 d-flex gap-2">` with Cancel first and `f.submit "Save", class: "btn btn-success btn-lg flex-grow-1"`, plus a `pb-5 mb-4` spacer so the bar doesn't hide the last field.
- `app/views/orders/deliveries/new.html.erb:44-49`: the same bar, Cancel `btn-warning`, "Record delivery" `btn-primary btn-lg flex-grow-1`.
- Upstream's Setup page, the screen Order Settings should copy (`app/views/settings/index.html.erb:43-48`): a `card mt-3` with a `card-footer` holding `f.submit "Save", class: "btn btn-lg btn-success"` then `link_to "Cancel", :back, class: "btn btn-lg btn-primary"`, in normal page flow, natural width, Save first.

## Fix

1. **Order Settings:** replace the fixed bar and spacer with upstream's card footer: Save (`btn btn-lg btn-success`) then Cancel (`btn btn-lg btn-primary`, still going to `orders_requests_path`). Same for the Inventory and other fork Setup pages if any copied the bar (none found by `grep fixed-bottom` today).
2. **Record delivery:** same treatment: buttons at the end of the form in page flow, "Record delivery" (`btn btn-primary btn-lg`) then Cancel (`btn btn-warning btn-lg`), natural width.
3. **Keep** the "Mark all received" bar on a request (`app/views/orders/requests/_receive.html.erb:82`): it's a single action at the foot of a long line list that people use on a phone while unpacking, and it sets `content_for :fixed_bottom_bar` so the page leaves room. That's a deliberate exception, not a form footer.

## Tests

- Update any system or view test that finds the buttons inside `.fixed-bottom` (`grep -rn fixed-bottom test/` on `feature/orders`).
- Order Settings controller/system test still saves and Cancel still returns to the requests list.

## Fork notes

Fork views only; no upstream files touched. Check the Orders help pages and gphelp screenshots of Order Settings and Record delivery after the change; recapture any that show the pinned bar.
