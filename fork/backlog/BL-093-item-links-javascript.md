# BL-093: Inventory item and supplier links accept `javascript:` URLs

| | |
|---|---|
| Kind | fork bug (security, `feature/inventory`) |
| Priority | medium |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | fix on `feature/inventory` |
| Upstream issue / PR | none yet |

## Summary

An item's **Link** and a supplier source's link are stored as typed and shown with `link_to`. A `javascript:` URL is accepted, so an inventory manager (or a CSV import) can store one, and anyone who clicks it, admins included, runs script in GatherPack. Order lines already refuse such links.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/views/inventory/items/show.html.erb:38`, `:101` and `app/views/inventory/reorder/index.html.erb:70`: `link_to @item.url` / `source.url`.
- `app/models/item.rb:24-28`, `app/models/item_source.rb:10`: no URL validation.
- `app/models/inventory/import.rb:208,225`: the import writes `url` unchecked.
- `app/models/order_line.rb:71`: `OrderLine.web_link?` is the existing check (http/https only); `order_requests_helper.rb:119-122` uses it.

## Proposed fix

Move `web_link?` into a small shared validator (`WebLinkValidator`) and use it on `Item#url`, `ItemSource#url` and `OrderLine`; the import reports a bad link as a row error. Views link only when `web_link?`, else show the text.

## Tests

- Model: `Item.new(url: "javascript:alert(1)")` invalid; `JaVaScRiPt:`, `data:` and leading-space variants too; `https://x.example` valid.
- Import: a row with a `javascript:` link is reported and not saved.
- View: an existing bad link renders as plain text.
- Ditto first: as an inventory manager, save the link; click it as an admin.

## Fork strategy notes

Fork-only (`feature/inventory`); the shared validator lives in the same branch, and `feature/orders` switches to it at the next sync.
