# BL-094: Uploads trust the browser's file type, and most attachments have no type or size check

| | |
|---|---|
| Kind | fork bug (security, `feature/security-series`) + upstream gap |
| Priority | medium |
| Status | not started (lead: confirm on Ditto first) |
| Added | 2026-11-28 |
| Code checked | `4d53cddfc` (hbr.56) |
| Planned branch | `feature/security-series` (direct uploads); attachment validations on each owning feature |
| Upstream issue / PR | none yet |

## Summary

Direct uploads check the content type the browser declares, not the file's bytes, and the attachment validator checks the same declared value. A signed-in member can upload an SVG labelled `image/png` past the "no SVG" rule and attach it as an avatar, where vips then processes it. Separately, order-line, delivery, item, unit, unit-event, funding-source and purchase attachments have no type or size validation at all (the `accept=` attribute is browser-side only). Rails' defaults serve SVG and HTML as downloads, so the risk is image processing on hostile files and very large uploads, not script.

Found by reading the code after the 2026-11-27/28 ZAP campaign of Ditto, in the areas a scanner can't reach (`security-scan` skill, run book).

## Where things are (hbr.56 `4d53cddfc`; check line numbers on the base branch when starting)

- `app/controllers/concerns/direct_upload_restrictions.rb:40-45`: declared `content_type` and size.
- `app/validators/attachment_validator.rb:12,19`: the no-SVG rule and the declared-type check.
- `app/models/person.rb:26`, `theme.rb:7`, `ledger_entry.rb:17`: the only validated attachments.
- Unvalidated: `FundingSource.documents`, `Purchase.receipts`, `OrderDelivery.photo`, `OrderLine.photo`, `Item.photo`, `ItemUnit.photo`, `ItemUnitEvent.photo`, inbound mailbox attachments (`app/mailboxes/incoming_mailbox.rb:19-23`).
- `people_helper.rb:21-29`, `order_requests_helper.rb:129-131`: vips variants.

## Proposed fix

1. `AttachmentValidator`: after upload, compare the blob's identified type (`Marcel` on the bytes; `blob.identify` / `analyze`) with the allowed list and reject a mismatch.
2. Add `attachment:` validations (types and a size cap, 10 MB like direct uploads) to every attachment listed above.
3. Variants only for identified raster images.

## Tests

- Upload SVG bytes declared `image/png`: refused as an avatar.
- Each model above: an `.html` file and an 11 MB file are refused.
- A real PNG still works everywhere.
- Ditto first: the SVG-as-PNG avatar as a student; what's served and whether vips fetched anything.

## Fork strategy notes

Direct-upload code is fork (`feature/security-series`); each attachment's validation goes on the branch that owns the model (orders, inventory, accounting).
