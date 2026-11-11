# BL-033: Search forms mark every field as required

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | started (`feature/search-form-asterisks`, see `FORK.md`) |
| Added | 2026-11-08 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Planned branch | see Status |
| Upstream issue / PR | none |

## Summary

Search and filter forms show a required asterisk on each field, though nothing on them is required. One helper override on `search_form_for` fixes all of them.
