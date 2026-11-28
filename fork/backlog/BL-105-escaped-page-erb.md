# BL-105: Dynamic Pages and Widgets don't escape `<%= %>` output

| | |
|---|---|
| Kind | upstream gap (hardening) + fork (widgets) |
| Priority | medium |
| Status | not started (confirmed: no live hole in HBR's Pages) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56); pages helper same in upstream `3d5ce8f96` |
| Planned branch | `feature/page-erb-escaping` (from `upstream/main`); widgets on `feature/widgets` |
| Upstream issue / PR | none yet |

## Summary

Dynamic Pages render with plain `ERB.new(content).result(binding).html_safe`, so `<%= %>` prints raw HTML. A page author who forgets `h()` lets a member's own name or answer run as script for every viewer of that page, public pages included. Widgets do the same. HBR's seven dynamic Pages were checked on Ditto (2026-11-28): every text output is escaped by hand, so nothing is open today; the risk is the next page written.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/helpers/pages_helper.rb:5`: `ERB.new(page.content).result(binding).html_safe`.
- `app/helpers/widgets_helper.rb:28`: same for widgets.
- Authoring needs the architect flag (`pages_controller.rb:58-70`); viewing follows the page's viewer level.

## Proposed fix

Render with Rails' escaping ERB (`ActionView::Template::Handlers::ERB::Erubi.new(content, escape: true)` or render the content as an inline template), so `<%= %>` escapes and `html_safe` strings (helpers, `raw`) pass through unchanged. Check every HBR Page renders identically before and after.

## Tests

- A page with `<%= "<b>x</b>" %>` shows the tags as text; `<%= raw "<b>x</b>" %>` and helper output still render.
- Each HBR Page's HTML is unchanged (render all seven on a copy, diff).

## Fork strategy notes

Upstream file edit (`pages_helper.rb`); widgets are fork. Confirm with Corey before any issue or PR.
