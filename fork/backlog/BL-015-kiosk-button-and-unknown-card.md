# BL-015: Kiosk: "Clock In" button, and an alert for an unknown card

| | |
|---|---|
| Kind | upstream feature |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-09 |
| Upstream base checked | `86ab397` (with `feature/kiosk-auto-clock-in` at `5f512ab`) |
| Planned branch | `feature/kiosk-auto-clock-in` (new commits; it isn't behind an upstream PR yet) |
| Upstream issue / PR | none yet |

## Summary

Corey asked for two changes after kiosk Phase 2 went to Ditto (2026-10-09):

1. **Rename the "Search" button to "Clock In".** It's the submit button beside the card box: `app/views/time_kiosk/_kiosk.html.erb:15`, `f.submit "Search"`.
2. **An unknown card number shows an alert.** Today a scan that matches no token silently shows Welcome again (`time_kiosk_controller.rb`, `find_token`: `@time_kiosk.token` is nil, so the tool becomes `welcome`, around line 35). It should show a banner that floats over the Welcome screen, like the auto clock-in banners ("You're clocked in…", "You're already clocked in…"). Use `flash.now[:warning]` (or `danger`) in the same place, for example "Card not recognized. Try again or see a mentor."

## Notes

- **Label vs. the setting:** "Clock In" fits when unassigned punches are off (`time_kiosk_allow_unassigned` false), because a scan clocks the person in. With the default (on), a scan only opens the profile. Decide whether the label is always "Clock In", or "Clock In" only when auto clock-in can happen and the upstream wording otherwise. Ask Corey; for upstream, a label that follows the setting keeps the default unchanged.
- **Token with no person:** a token that exists but belongs to no person (or to a Hook) shows the `not_found` screen (Phase 1). Consider whether that case should also become a banner on Welcome, so both kinds of bad card look the same.
- Keep the message generic: it must not reveal whether a number exists.
- **Rate limit:** unknown numbers still count toward the 60 lookups a minute.

## Hooks

None. Neither change creates, updates or destroys records.

## Tests

- In a new test file or `test/controllers/time_kiosk_auto_clock_in_test.rb` (Phase 2's), not Phase 1's `time_kiosk_controller_test.rb`: an unknown card value renders Welcome with the alert, and creates nothing.
- The button label, under each setting if the label follows the setting.
