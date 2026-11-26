# BL-090: The rich-text editor bundles a DOMPurify with known advisories

| | |
|---|---|
| Kind | upstream dependency |
| Priority | medium |
| Status | not started (waiting on a Trix release) |
| Added | 2026-11-25 |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | none until a fixed `action_text-trix` exists; then `feature/trix-bump` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

ZAP's Retire.js check flags `/assets/trix-*.js` (High, medium confidence): Trix 2.1.19 bundles DOMPurify 3.4.2, and DOMPurify 3.4.12 through 3.4.17 fixed 13 advisories (GHSA-gvmj-g25r-r7wr, GHSA-c2j3-45gr-mqc4, GHSA-r47g-fvhr-h676 and others listed in the report). Trix uses DOMPurify when HTML is pasted or loaded into the editor. Stored rich text is cleaned again on the server by Rails' sanitizer before it's shown, so the exposure is mainly inside the editor (pasting, or opening crafted content someone else saved), not on reading pages.

## Where things are (upstream `3d5ce8f96`)

- `Gemfile.lock`: `action_text-trix (2.1.19)`, pulled in by `actiontext (~> 2.1.15)`.
- `config/importmap.rb:12`: `pin "trix"` (served from the gem).
- `package.json:15`: `"trix": "^2.1.1"` (not what's served).

## Proposed fix

1. Check for an `action_text-trix` release that bundles DOMPurify 3.4.17 or later. If one exists: `bundle update action_text-trix`, regenerate `Gemfile.lock` (never hand-merge), run the Action Text system specs.
2. If none exists: open an issue on basecamp/trix asking for the DOMPurify bump (with the advisory list), and recheck at each weekly sync.

## Tests

- Existing Action Text / rich-text system specs pass.
- A ZAP passive scan of the served `trix-*.js` no longer reports Vulnerable JS Library.

## Fork strategy notes

The lockfile is upstream's, so the bump belongs upstream as an issue or PR; confirm with Corey first. Lower priority than BL-088: an enforced CSP blunts most of what these advisories allow.
