# BL-037: The calendar notes page crashes when a note links to a record

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | new |
| Added | 2026-11-08 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Planned branch | none yet |
| Upstream issue / PR | none |

## Summary

`app/views/calendar_notes/_calendar_note.html.erb:8` calls `as_badge calendar_note.noteable, true`, but `as_badge(obj, **opts)` takes one positional argument, so `/calendar_notes` raises `ArgumentError`.
