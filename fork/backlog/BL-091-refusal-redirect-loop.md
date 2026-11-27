# BL-091: A refused page can redirect to itself forever

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | not started |
| Added | 2026-11-27 |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | `feature/refusal-redirect-loop` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

When Pundit refuses a request, `ApplicationController#pundit_not_authorized` sends the person back to the page they came from (`redirect_back_or_to root_path`). If the refused page is the one they came from, the redirect points at the refused page again. The browser follows it, gets refused again with the same Referer, and stops only with "too many redirects". The notice never shows.

A member hits this on an ordinary path. They have a page open (a form's answers, say) and lose access to it: they're taken off the team, or the form is closed to them. They then change a filter on that page. The filter's GET is refused and redirects back to the page itself, which is refused in turn, and so on. Browsers keep the original Referer across redirects, so every hop repeats the loop.

The ZAP scan of Ditto as a mentor found it. ZAP follows redirects and keeps the Referer, so each refused page on the form answers screen looped until ZAP gave up: about 1,600 requests a minute and 17,000 refusals in ten minutes, and the attack rules stalled.

## Where things are (upstream `3d5ce8f96`)

- `app/controllers/application_controller.rb:61-63`: `pundit_not_authorized` calls `redirect_back_or_to root_path, notice: "You are not allowed to do that"`. Rails' `redirect_back_or_to` uses `request.referer` whenever one is present and same-origin.
- `app/controllers/people_controller.rb:72` and `:79` use `redirect_back_or_to` after other refusals. They're less exposed, but have the same shape.

## Proposed fix

In `pundit_not_authorized`, go back only when the Referer is a different page: compare the Referer's path with `request.path`. If they're the same, or there's no Referer, redirect to `root_path` with the same notice. Use one small private helper (`safe_back_location`) so the two `people_controller` calls can use it too.

## Tests

- Request spec: a signed-in member GETs a form they can't see, with `Referer` set to that form's URL (with and without a query string). Expect a redirect to `/` and the "You are not allowed to do that" notice.
- Request spec: with `Referer` set to another page, the redirect still goes back to that page, as today.

## Fork strategy notes

Upstream file edit (`application_controller.rb`, `people_controller.rb`): list both in `FORK.md` "Upstream files touched". Small enough to offer upstream as a bug fix; confirm with Corey before any issue or PR.
