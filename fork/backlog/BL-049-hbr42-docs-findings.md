# BL-049: Mismatches found while documenting hbr.42

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | medium |
| Status | shipped hbr.43 (#1 310, #3 312, #4 313; #2 not a bug: To receive is in More; demo: Demo Admin added, parent on Parents; real names are fine) |
| Added | 2026-11-16 |
| Commit checked | `v0.0.0-hbr.42` (demo) |
| Planned branch | `feature/my-gatherpack-activity`, `feature/my-gatherpack-orders`, `feature/inventory`, `feature/checklists`; demo data on hbr/platform |
| Upstream issue / PR | none |

## Summary

Reported by the help-guide session while updating guides for hbr.42. The guides leave these out.

## Screens

1. **My activity: "Signed up" records never show "Counts toward".** A sign-up that a checklist counts (a demo member's stocking shifts count toward a concessions checklist) shows no "Counts toward" line, in the guardian view too.
2. **To receive isn't in a member's menu.** The hbr.42 menu code says it "stays in More", but members only reach it from Home's To do row.
3. **Ticked boxes still look empty** (white tick on light gray): Active on New item and New place, Preferred on Where to buy. BL-048 #7's fix doesn't show on demo. The cause is probably the app-wide `.form-check-input:checked` rule in `_forms.scss`; check before fixing only inventory forms again.
4. **Checklist column filter says "Below Minimum"**; the result badge says "Below minimum".

Not a bug: a re-approval has only Approve and Decline, as orders-spec §3.4 says. The changed-screens list given to the guide session was wrong and has been corrected.

## Demo data (`fork/demo_db`)

5. A concessions event is all-day and counts as 24 h on a demo member's activity.
6. Capture prepares still queue "To approve" emails to approvers holding a real badge (Mentor Ready). They're discarded (no gateway, snapshot restore), but the demo's approvers should be personas only.
7. The demo parent persona is on no team.
8. The rebuild re-anonymized names, and the protected real-name accounts are now ordinary Student Leadership members. Several older captures need adjusting.
