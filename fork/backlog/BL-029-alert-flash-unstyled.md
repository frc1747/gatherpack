# BL-029: Error messages sent as `alert` show with no colour

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | started (`feature/alert-flash-style`, see `FORK.md`) |
| Added | 2026-11-04 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Branch | `feature/alert-flash-style` (from `upstream/main`) |
| Upstream issue / PR | none |

## Summary

Rails' usual key for an error message is `flash[:alert]` (`redirect_to ..., alert: "..."`). GatherPack's layout turns each flash key into a Bootstrap class with `ApplicationHelper#flash_to_class`, which maps `notice` to `alert-info` and passes every other key through unchanged. So `alert` becomes `alert-alert`, which Bootstrap doesn't define. The message shows as plain text with no coloured box, which makes it easy to miss.

Found 2026-11-04 in review of `feature/blocked-delete-message` (BL-019), whose refused-delete message uses `alert:`.

## Where things are (upstream `3fa5700`)

- `app/helpers/application_helper.rb:56-65`: `flash_to_class`. Only `notice` is mapped.
- 5 `alert:` uses in `app/controllers` (`git grep -c "alert:" upstream/main -- app/controllers`), plus Devise, which sets `flash[:alert]` for failed sign-ins and similar.

## Proposed fix

Map `alert` to `danger` in `flash_to_class`, next to `notice`, and give it the `danger` icon in `flash_to_icon`. The Devise layout (`layouts/devise.html.erb`) doesn't use the helper (it hard-codes `alert-secondary`), so failed sign-ins look the same; changing that is a separate choice.

## Hooks

None. Display only.

## Tests

- A helper test: `flash_to_class("alert")` is `alert-danger`, `notice` is still `alert-info`, and other keys (`warning`, `success`) pass through.

## Fork strategy notes

One upstream helper line and a test. Upstream-intended; confirm with Corey before any issue or PR.
