# BL-011: Accounting (account status from any source, and billing)

| | |
|---|---|
| Kind | fork-only feature (built with upstream naming, so it could be offered later; Corey decides) |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-07 |
| Planned branch | `feature/accounting`, based on `feature/person-fields` (declared dependency), plus `feature/my-gatherpack-accounting` |
| Upstream issue / PR | none |

GatherPack shows each person's account status (what's owed, paid, balance remaining, milestones, Paid / Partly paid / Overdue) from the group's money records, with per-person payment plans, reminders, a family view and treasurer totals. Where the records come from is a separate, pluggable source: QuickBooks Online, GatherPack's own ledgers, or a spreadsheet upload, and another accounting package can be added as a gateway without touching the rules. A later Billing part lets GatherPack create the bills in the source, which stays the record.

Design: [`fork/specs/accounting-spec.md`](../specs/accounting-spec.md).
