# BL-037: The calendar notes page crashes when a note links to a record

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | live hbr.41 (`feature/calendar-note-badge`, see `FORK.md`) |
| Added | 2026-11-08 |
| Upstream commit checked | `3fa5700` (`upstream/main`) |
| Planned branch | `feature/calendar-note-badge` |
| Upstream issue / PR | none |

## Summary

`app/views/calendar_notes/_calendar_note.html.erb:8` calls `as_badge calendar_note.noteable, true`, but `as_badge(obj, **opts)` takes one positional argument, so `/calendar_notes` raises `ArgumentError`.
