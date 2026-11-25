# BL-011: Accounting (account status from any source, and billing)

| | |
|---|---|
| Kind | fork-only feature (built with upstream naming, so it could be offered later; Corey decides) |
| Priority | medium |
| Status | shipped hbr.54 (flag off; Intuit sandbox check still open) |
| Added | 2026-10-07 |
| Branch | `feature/accounting` and `feature/my-gatherpack-accounting` (see [FORK.md](../../FORK.md)) |
| Upstream issue / PR | none |

GatherPack shows each person's account status (what's owed, paid, balance remaining, milestones, Paid / Partly paid / Overdue) from the group's money records, with per-person payment plans, reminders, a family view and treasurer totals. Where the records come from is a separate, pluggable source: QuickBooks Online, GatherPack's own ledgers, or a spreadsheet upload, and another accounting package can be added as a gateway without touching the rules. A later Billing part lets GatherPack create the bills in the source, which stays the record.

Design: [`fork/specs/accounting-spec.md`](../specs/accounting-spec.md).

## Built

All seven rollout steps (spec §16.4) are on `feature/accounting`, behind `feature_accounting` (off by default):

1. QuickBooks read side: connect, sync, changes job and notifications, the Records page.
2. Customer links and the Customers page.
3. Rules, the Account Status pages, the Account tab and the statement.
4. Rule actions (badges, person fields).
5. Ledger and file sources (upload, preview, apply).
6. Payment plans, reminders and treasurer totals.
7. Billing runs: QuickBooks invoices behind "Let GatherPack create invoices", ledger entries, and a CSV for file sources.

`feature/my-gatherpack-accounting` adds account rows to Home and each Family ward card. Sample data: a file source, "Northwind dues sheet", with rules, actions, a payment plan and a billing run.

Decisions made while building, now in the spec:

- Disconnect is a confirm page; only its POST disconnects (§4.3).
- Unlinking is remembered as a dismissal; sub-customers under a linked parent count as covered with the rollup on (§7).
- A split ledger parent counts for what its children don't cover (§5.3); "Team for new ledgers" comes before the rule's team (§5.5).
- On a rule with any payment plan, non-admins see only the status for everyone, apart from the person's own line (§8.4).
- Turning a rule off or deleting it takes back only what it gave (§9).
- The rule page's row is Edit, Bill people, More (§11.3).
- Gateway settings get tick boxes and choices through a 4-line seam in the upstream gateway form (§16.2).

## Still to do

The manual Intuit sandbox check needs the owner:

1. An Intuit developer account (a group-owned email) and an app with the Accounting scope, and its sandbox company.
2. The app's development client ID and secret, entered on a new QuickBooks source (Setup → Gateways).
3. Redirect URIs registered in the Intuit app: `http://localhost:3000/accounting/quickbooks/callback`, and `https://<host>/accounting/quickbooks/callback` for any staging host used.
4. For notifications: the webhook `https://<host>/gateways/<gateway id>/webhook` (CloudEvents; Customer, Invoice, Payment, CreditMemo, Item) with its verifier token copied into the source, and an access-proxy bypass for that path. Without it, the 15-minute changes job covers it.
5. An architect who clicks Connect while signed in to Intuit as the sandbox company's admin.
6. Then confirm: connect, disconnect, reconnect; Intuit's test event; a sandbox payment changing an invoice's balance; a billing run creating, emailing and syncing back two invoices. Also confirm the fixtures' assumptions: a voided invoice has `TotalAmt` 0 and a private note starting "Voided"; `include=invoiceLink` returns `InvoiceLink`; CloudEvents `type` is `qbo.<entity>.<operation>.v1`; minor version 75 is accepted; CDC deletes come back with `status: "Deleted"`.
