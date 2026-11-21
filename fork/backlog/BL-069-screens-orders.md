# BL-069: Orders screens to the standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | `feature/orders`, `feature/order-inventory`; after BL-062 |
| Upstream issue / PR | none |

## Summary

An order request's page holds 23 buttons across its slots (lines, decision, purchase, receive, timeline); most show only in one state, but a buyer can still see eight at once. Purchases and To buy repeat the same four row actions (Mark delayed, Change quantity, Split, Cancel item) in four colours. The settings page copies upstream's large green/blue Settings buttons. Keep the request page's decision bar (it's the job of the person whose turn it is) and move everything else into the standard. Standard: `fork-spec` "Screen design"; reasoning: `fork/specs/screen-standard-spec.md`.

## Screens

| Screen | Now (`c4700b175`) | Change |
|---|---|---|
| Request `orders/requests/show.html.erb` + `_actions`, `_decision`, `_purchase`, `_receive`, `_timeline` | Finish request, Update, Change (`btn-warning`), Delete draft, Cancel request (`btn-danger`), Order again, Follow/Stop following, Approve/Ask for changes/Decline, Open To buy, Receive, Receive the rest, Comment | header state line ("Waiting for approval by Purchasing", "Ordered Nov 20"); `_action_row` with the one job for the viewer and state (Finish request, Approve, Open To buy or Receive) and More (Edit/Change, Order again, Follow/Stop following, Delete draft or Cancel request last). Decision bar keeps Approve (`btn-success`), Ask for changes (`btn-secondary`), Decline (`btn-danger`) side by side: a decision, not a state. Comment stays in the timeline |
| Request form `orders/requests/{new,edit}` `_form.html.erb:87-92` | Submit for approval, Save (`btn-secondary`), Send back for approval, Save changes | Cancel (`btn-secondary`), Save draft (`btn-secondary`), Submit for approval (`btn-primary`, last) |
| Purchases, To buy `orders/purchases/{index,show,to_buy}.html.erb` | row actions Mark delayed (`btn-warning`), Change quantity, Split (`btn-secondary`), Cancel item (`btn-danger`); filter links as full buttons | per line: the line's job button stays (`btn-sm btn-primary`; "Record in ledger" on a purchase) and a small More (Mark delayed, Change quantity, Split, Cancel item last); filters as `_filter_bar` pills |
| Deliveries `orders/deliveries/{index,new}.html.erb` | `btn-lg` toggle buttons; Record delivery `btn-lg btn-primary`, Cancel `btn-lg btn-warning` | filter pills; Cancel `btn-secondary`, Record delivery (`btn-primary`) — large size kept on phone only (`orders-phone` CSS) |
| Settings `orders/settings/show.html.erb` | Save `btn-lg btn-success`, Cancel `btn-lg btn-primary` | Cancel `btn-secondary`, Save `btn-primary` (pinned, BL-055); "Add a row" `btn-sm btn-outline-secondary` |
| Vendors, funding sources, approval steps (`orders/vendors/*`, `orders/funding_sources/*`, `orders/approval_steps/*`) | Cancel `btn-warning`; approval steps rows Edit `btn-outline-warning`, Retire/Restore | Cancel `btn-secondary`; rows per "Defined things" (small Edit, arrows, Retire) in `btn-sm btn-outline-secondary`; `pattern_test` gets a breadcrumb |
| Reports `orders/reports/*`, `orders/funding_sources/report` | Download CSV `btn-secondary` in the footer | Download CSV at the right of the filter bar |
| Reorder draft `order_inventory/reorder_drafts/new.html.erb` | no breadcrumb | breadcrumb; Cancel, Create draft request |

## Works differently

- A request shows one job button and More; Edit, Follow and Cancel request move into More.
- Line actions on Purchases and To buy move into a small More per line.

## Tests

- Request page for each role and state (requester draft, approver waiting, buyer approved, receiver ordered): exactly one job button outside More, the decision bar for the approver, Cancel request last in More with its confirm.
- Purchases/To buy: each line action from More still works; Cancel item keeps its confirm.
- Settings saves with the new footer; pinned behaviour unchanged.
- Existing orders and order-inventory tests stay green; none weakened (update selectors that found buttons by colour).

## Fork notes

- No flag (`feature_orders` gates it). No upstream files touched.
- Retake gphelp screenshots: request page per role, request form, To buy, Settings.
