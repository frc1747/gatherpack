# Spec: Accounting

GatherPack answers questions about people from the group's money records: "has this person's bill been paid, or are they behind?", "how much is left?", "what's due next?". The money records can come from an accounting system (QuickBooks Online first), from GatherPack's own ledgers, or from a spreadsheet upload. The answers, who may see them, and what happens when they change are the same whichever source is used. A later part lets GatherPack create the bills too.

Backlog item: [BL-011](../backlog/BL-011-accounting-integration.md). Code facts checked against `hbr/integration` `9f033db7d`. Decisions are in §17.

## 0. In plain words

Two separate things, joined by one plain table:

1. **Where the money data comes from (a source).** The QuickBooks connection is a source. It signs in to QuickBooks, copies the customers, invoices, payments and credits, and keeps the copy current. GatherPack's own ledgers can be a source instead, and so can an uploaded spreadsheet. Someone can write a source for Xero or Wave without touching anything else.
2. **What the group wants to know (the rules).** "2027 Membership Dues: owed, paid, balance remaining, deposit by one date and the rest by another, Paid / Partly paid / Overdue." The rules decide what's owed, the status, the milestones, who sees what, the reminders and the badges. They never look at QuickBooks' own data. They read the plain table.

Between them sits the **plain table** (`accounting_records`, §3.4): every source turns its records into the same columns (who it's for, charge or payment, total, balance, due date, products). So yes: the QuickBooks gateway is one thing, and dues tracking is another. Dues tracking works the same on ledgers, a spreadsheet, or a future Xero source.

## 1. Goal

Let a group answer money questions per person, from whichever books it keeps, with nothing about any one group's dues written into code.

The feature has five layers. Each is generic; what a group wants is configuration:

1. **Sources.** A `Gateway` registered under `:accounting` that copies records from somewhere (QuickBooks, ledgers, a file) and keeps the copy current (§4–§6).
2. **Plain records.** The copy, stored with the source's raw data plus provider-neutral columns that every source fills the same way (§3.4).
3. **Customer links.** Which GatherPack person (or people) each customer represents, suggested automatically and confirmed by an admin (§7).
4. **Rules.** Saved questions ("2027 Membership Dues", "Travel fee", "Total given this year"), each producing one result per person, with milestones, per-person payment plans, reminders, visibility and actions (§8–§10).
5. **Billing.** GatherPack authors charges and writes them into the source, which stays the record (§12).

Examples this must handle without code changes:

- **Dues per member, in stages.** One bill per member for a dues product. The rule tracks the balance remaining against dated milestones: some paid by one date, all paid by a later one. Result: Paid / Partly paid / Not yet paid / Overdue / Not invoiced, plus the balance remaining. Visible to the member, their guardians and their leaders, and copied into a hidden profile field that other features (an eligibility checklist) test.
- **Credits of any kind.** Scholarships, fundraising credit or a refund applied to the bill lower the balance remaining exactly as a payment does. The rule doesn't care where the money came from, and non-admins only ever see "Credit".
- **Dues per family.** One bill per household covering every child. The same rule, with the customer linked to several people.
- **A second fee.** "Travel fee 2027": a new rule filtered on a different product.
- **Totals.** "Amount given in 2026", summed from receipts and invoices for a donor, visible to admins only.
- **A group whose ledgers are its books.** A group that keeps a ledger per member, adding a charge when dues are set and a payment when money comes in, uses the ledger source and gets the same statuses, milestones and reminders.
- **A group with only a spreadsheet.** The treasurer exports from their accounting program, or keeps a sheet by hand, and uploads it.
- **A hardship plan.** One member pays in four smaller amounts on their own dates; everyone else follows the rule's milestones.
- **Anything else.** A custom rule with architect-written Ruby.

### 1.1 Non-goals

- **Changing the books.** GatherPack never edits, voids or deletes anything in a source and never records payments. The only writes are the ones Billing makes, when it's turned on (§12): new charges and new customers, and emailing a charge it just created.
- **Taking payments.** Families pay through the source's own pay link (QuickBooks' invoice link, or a ledger's Pay page), which we only display.
- **Copying one source into another** (QuickBooks into ledgers, §1.2).
- **Line-level payment status.** Accounting systems apply payments to whole bills, not lines. A bill holding a matching line counts as a whole (§8.3).
- **Sources other than the three built in.** The interface is documented (§3.2, §3.5) so another can be added; only QuickBooks Online, ledgers and the file source are built.
- **QuickBooks Desktop.** It has a different API; the file source covers it through export.
- **Several companies at once.** The design allows several sources, and every record carries its gateway. Tests and docs cover one source per rule.

### 1.2 Ledgers: what was rejected, and what is supported

**Rejected: copying QuickBooks into ledgers.** Mirroring every invoice in as a charge and every payment as a credit makes a second set of books beside the accounting system:

- **Copies drift.** Team managers can edit and delete ledger entries, so a mirrored payment could stop matching the books, and the sync would have to fight those edits.
- **A ledger entry carries no due date and no "applied to"**, so the copy would lose exactly what "paid in full on time" needs.
- **The wrong Pay button.** A ledger's Pay goes through the Stripe gateway into GatherPack, not to the group's own payment route.

**Supported: ledgers as the source.** For a group whose ledgers *are* its books, the ledger source (§5) reads them directly. Nothing is copied into them; the rules read the plain records like any other source's, and the ledger's own Pay page is the right button for that group.

**Ledger visibility is unchanged.** `LedgerPolicy::Scope` shows every ledger of a team to that team's members, so per-member ledgers on one team expose everyone's payments to everyone. This feature doesn't change that. The rules layer has its own permissions (§8.2), so a group can keep ledgers on an admin-only team and still show each member their own status. The ledger setup page says so (§5.6).

The statement (§11.5) gives members and guardians a ledger-style view from any source, without a second set of books.

## 2. What exists today (and what we reuse)

| Piece | Where (upstream unless noted) | Use |
|---|---|---|
| Gateways | `app/models/gateway.rb`: `Gateway.register(klass, svc)`, `Gateway.registered(svc)`, `configuration` (jsonb), `secrets` (encrypted, kept out of the audit log; `feature/security-series`), `fields`, `finish_setup`, `routes`, `verify_webhook`, `handle_webhook`, `webhook_headers` | Every source is a `Gateway` subclass registered under a new `:accounting` service. Reuses the gateway pages (architects only, `GatewayPolicy < ArchitectPolicy`) and the `routes` buttons. |
| Gateway webhooks | `POST /gateways/:id/webhook` → `verify_webhook` → `ProcessGatewayWebhookJob` → `handle_webhook(payload, headers)` | QuickBooks change notifications. No new webhook route. |
| Stripe gateway | `app/models/gateway/stripe_gateway.rb` | The pattern: `store_accessor :secrets` for keys, `store_accessor :configuration` for settings, signature check in `verify_webhook`. |
| Encryption keys | `config/initializers/active_record_encryption.rb` (`feature/security-series`) | Encrypts the token table (§4.4). No new initializer. |
| Ledgers | `Ledger` (per team; `balance_cents` = finalized, non-failed top-level entries), `LedgerEntry` (`parent_id` splits, `failed`, `finalized`, `metadata` jsonb, `remark`, tags), `LedgerOwnership` (polymorphic owner), `LedgerTag` | The ledger source (§5). Not changed. |
| Audiences | `AudienceLevels`, `AudienceAccess` (`feature/person-fields`) | Who may see a rule's results and amounts: `admin`, `self`, `leaders`, `self_and_leaders`, `guardians`, `family`, `team`, `everyone`, plus badge grants. |
| Guardianship | `Person#guardians`, `#wards` (`feature/person-fields`) | Guardians see their wards' results when a rule's level includes guardians; email matching suggests a guardian's wards (§7.2). |
| Person fields | `PersonField`, `PersonFieldValue` (`feature/person-fields`) | A rule can write its result into a person field. Trusted callers leave `acting` unset. |
| Badges | `Badge`, `BadgeAssignment` | A rule can add and remove a badge (§9.1). |
| Hooks | `CanBeHooked`, `GatherPack::HookCatalog.register_targets` / `register_events` (`feature/extension-registries`) | Record and domain events (§14), registered from the feature's initializer. `Hook#run`'s eval pattern is also how custom rules run. |
| Routes and recurring jobs | `config/routes/*.rb` and `config/recurring.d/*.yml` (`feature/recurring-routes-seams`) | `config/routes/accounting.rb`, `config/recurring.d/accounting.yml`. No edit to `config/routes.rb` or `config/recurring.yml`. |
| Profile tabs | `GatherPack::Feature::ProfileTab` (`feature/profile-tabs`) | The Account tab (§11.4), as checklists and commitments add theirs. |
| My GatherPack | `MyGatherpack.register_section` (`feature/my-gatherpack`), the Family page's ward card (`feature/my-gatherpack-family`) | The Account section and ward rows (§11.6), in a connector branch. |
| Summaries | `GatherPack::Digests.register`, `delivery_for` (`feature/digests`) | Reminders can go in the daily summary (§10), when that seam is merged. |
| Reports and widgets | `Report`, `feature/widgets` | Read `AccountingRuleResult` from ERB like any other model. |
| Feature registry | `GatherPack::Features.register` | `:accounting` in the Finance section, default off. |
| Background jobs | Solid Queue | Sync, evaluation, reminders, billing. |
| HTTP | Ruby `Net::HTTP` | No new gem. |

## 3. Layers and the source interface

### 3.1 The layers in code

| Layer | Knows about | Never touches |
|---|---|---|
| Source (`Gateway::QuickbooksGateway`, `Gateway::LedgerSource`, `Gateway::FileSource`, any third-party gateway) | Its own system's API or tables; how to turn a raw record into the neutral columns (`normalize`); what it can do (`capabilities`) | Rules, results, people |
| Plain records (`AccountingRecord`) | Neutral columns + raw `data` | — |
| Links (`AccountingCustomerLink`) | `gateway_id` + `customer_external_id` → person | Raw data |
| Rules, results, plans, reminders, screens (`Accounting::*`) | Neutral columns, links, capabilities | Raw `data` (only `custom` rules may read it), source class names |
| Billing (`Accounting::BillingRun`) | People, links, rules; calls `Provider#create_charge` / `create_customer` / `send_charge` | How a source stores a charge |

Rules, links and records all carry `gateway_id`. A test greps `app/models/accounting/` outside the sources' own folders for QuickBooks field names (`TotalAmt`, `LinkedTxn`, `UnappliedAmt`, `ItemRef`, `CustomerRef`) and fails if any appear (§15).

### 3.2 `Accounting::Provider`

Every source is a `Gateway` subclass that calls `Gateway.register(self, :accounting)` and includes this module:

```ruby
module Accounting::Provider
  # What this source can do (3.3). Screens and jobs check it; nothing else does.
  def capabilities = Set.new

  # The source's own record types, each with the role it normalizes to.
  # e.g. { "Customer" => :customer, "Invoice" => :charge, "Payment" => :payment }
  def entity_types = raise NotImplementedError

  # Which of those types are locations rather than categories (QuickBooks:
  # Department), so screens list them apart.
  def location_entity_types = []

  # Yields raw attribute hashes for every record of the type. Full sync (13.1)
  # marks anything not yielded as deleted.
  def each_record(entity_type) = raise NotImplementedError

  # Turns one raw record into the neutral columns (3.4), as a hash.
  def normalize(entity_type, data) = raise NotImplementedError

  # The external id and version marker of a raw record.
  def external_id(entity_type, data) = raise NotImplementedError
  def revision(entity_type, data) = nil

  # :change_feed -- yields [entity_type, data, deleted?] changed since time.
  def each_change(entity_types, since) = raise NotImplementedError
  def change_window = nil          # how far back each_change reaches, if limited

  # :notifications -- one record, after a webhook named it.
  def fetch_record(entity_type, external_id) = raise NotImplementedError

  # :create_charges -- creates one charge for a billing line (12.3) and
  # returns its external id. Must be safe to call twice with the same
  # line.request_id: the second call returns the first charge.
  def create_charge(line) = raise NotImplementedError

  # :create_customers -- creates a customer for a person, returns its external id.
  def create_customer(person, email:, request_id:) = raise NotImplementedError

  # :send_charges -- emails a charge this source created.
  def send_charge(external_id, email:) = raise NotImplementedError

  # Where the source's connection stands, for the Account Status page:
  # :ok, :needs_attention (with a message), :not_connected.
  def connection_state = :ok
end
```

`normalize` must be pure: same input, same columns. Sources that need more than one record to compute a column (the ledger source's first-in-first-out matching, §5.3) put what they computed into the raw hash they yield from `each_record`, so `normalize` still sees one record.

### 3.3 Capabilities

| Capability | Means | Without it |
|---|---|---|
| `:change_feed` | `each_change` works; the 15-minute changes job (§13.1) runs. | Only full syncs (or the source's own push, as ledgers do). |
| `:notifications` | The source pushes webhooks and `fetch_record` works. | No webhook handling. |
| `:due_dates` | Charges carry `due_on`. | The rule form warns when a rule has no milestones: "Nobody will ever be Overdue" (§8.3). Billing hides the due date field. |
| `:pay_links` | Charges may carry `pay_url`. | No **Pay online** anywhere, and the rule form hides "Show pay links". |
| `:deep_links` | Records carry `external_url`. | No "Open in <source>" links for admins. |
| `:create_charges` | `create_charge` works. | **Bill people** offers a CSV instead (§12.6). |
| `:create_customers` | `create_customer` works. | Billing skips people with no linked customer, with the reason. |
| `:send_charges` | `send_charge` works. | No "Email the invoices" choice. |
| `:upload` | Records come from an uploaded file (§6). | No Upload button. |

A capability can depend on settings: the QuickBooks source has `:create_charges`, `:create_customers` and `:send_charges` only while "Let GatherPack create invoices" is on (§4.6).

| Source | Capabilities |
|---|---|
| QuickBooks | `change_feed`, `notifications` (with a verifier token), `due_dates`, `pay_links`, `deep_links`, and with writing on: `create_charges`, `create_customers`, `send_charges` |
| Ledgers | `pay_links` (while a `:payment` gateway exists), `deep_links`, `create_charges`, `create_customers` |
| File | `due_dates`, `upload` |

### 3.4 `accounting_records`, prefix `acr`

One row per source record: the raw payload plus neutral columns filled by `normalize`. The neutral columns sit on this table rather than a sibling: they're one-to-one with the raw record, written in the same upsert, and every rule query filters on them, so a join would add a table to every read and a way for the two to drift.

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | |
| `entity_type` | string, required | The source's own name: `Invoice`, `LedgerEntry`, `row`. Only sources and admins' Records page use it. |
| `external_id` | string, required | |
| `revision` | string | The source's version marker. A record whose revision hasn't changed isn't saved again. |
| `data` | jsonb, required | The raw record. Read only by its source, the Records page and `custom` rules. |
| `role` | string, required, indexed | `customer`, `charge`, `receipt` (charged and paid at once), `payment`, `credit`, `refund`, `item`, `category`, `other` |
| `customer_external_id` | string, indexed | Who it's for. A customer's own id for `customer` rows. |
| `parent_external_id` | string | `customer` rows: the parent customer, for rollup (§7.1). |
| `name` | string | `customer`, `item`, `category` rows. |
| `email` | string | `customer` rows, for matching (§7.2). |
| `reference` | string | `customer` rows: the value the `reference` strategy matches (§7.2). |
| `active` | boolean, default true | `customer` and `item` rows. |
| `number` | string | Document number ("1042"). |
| `txn_date` | date, indexed | |
| `due_on` | date | `charge` rows. |
| `total_cents` | bigint | Positive for every role; the role says which way the money went. |
| `balance_cents` | bigint | `charge`: what's still owed on it. `credit`: what's left to apply. |
| `voided` | boolean, default false | Rules skip voided rows. |
| `lines` | jsonb | `[{ "item_id":, "class_id":, "amount_cents": }]`, nested groups flattened. |
| `item_ids` | string[], GIN | Every `item_id` in `lines`. |
| `class_ids` | string[], GIN | Categories on the record or its lines (QuickBooks classes, ledger tags are items not classes). |
| `location_ids` | string[], GIN | QuickBooks Locations (departments); empty elsewhere. |
| `applied_to` | jsonb | `payment`, `credit`, `refund` rows: `[{ "external_id":, "amount_cents": }]`, the charges it was applied to. |
| `unapplied_cents` | bigint | `payment` and `credit` rows: money not applied to any charge. |
| `pay_url` | string | `charge` rows, with `:pay_links`. |
| `external_url` | string | With `:deep_links`. Admins only. |
| `public_label` | string | Safe for anyone who may see amounts: the role word, and for charges the number and item ("Invoice 1042 · Dues"). Never a memo, note or credit reason (§11.8). |
| `description` | text | Memo, remark, private note. Admins only. |
| `external_updated_at` | datetime | |
| `deleted_at` | datetime | Set when the source reports a delete or a full sync no longer sees it. Rules ignore deleted rows. Hard-deleted only with the gateway. |
| `fetched_at` | datetime | |
| timestamps | | |

Unique on `(gateway_id, entity_type, external_id)`. Model: `include CanBeHooked`, **no** `has_paper_trail` (the source is the history; copies of every financial record in the audit log would be needless exposure). `AccountingRecord` validates `role` and that money columns are non-negative.

`public_label` words come from the source's role labels, which an admin can rename on the source's page ("Invoice", "Payment", "Credit", "Refund", "Receipt"): words tied to code behavior, with editable labels.

### 3.5 Adding a source

To add Xero, Wave or anything else, a developer writes one gateway class and nothing in the rules layer:

1. `class Gateway::XeroGateway < Gateway`, `Gateway.register(self, :accounting)`, `include Accounting::Provider`. Keys in `store_accessor :secrets`, settings in `store_accessor :configuration`, `fields` for the edit page.
2. `entity_types`: the system's record types and the role each becomes.
3. `each_record` and `external_id` / `revision`: a full read. That alone makes the source usable (full sync weekly, or on **Sync now**).
4. `normalize`: fill the columns in §3.4. The rules depend on `role`, `customer_external_id`, `total_cents`, `balance_cents`, `due_on`, `voided`, `item_ids`, `applied_to`, `unapplied_cents` and `public_label` being right; the rest are optional. Never put a memo or note into `public_label`.
5. Optional, each with its capability: `each_change` + `change_window`, `verify_webhook` + `handle_webhook` + `fetch_record`, `pay_url`, `external_url`, `create_charge`, `create_customer`, `send_charge`.
6. Customers page buttons via `routes`; connection state via `connection_state`.
7. Tests: include `Accounting::ProviderContract` (a shared Minitest module, §15) in the source's test, which feeds fixtures through `normalize` and checks the columns, idempotent `create_charge` and that undeclared capabilities raise `NotImplementedError`.

Sign-in flows, token tables and API clients are the source's own business: QuickBooks' are in §4 and live under `app/models/accounting/quickbooks/`.

## 4. QuickBooks Online source

### 4.1 Facts this design depends on

Checked when the design was first written; re-verify each against Intuit's documentation when building.

- **Sign-in.** OAuth 2.0 authorization-code flow with the `com.intuit.quickbooks.accounting` scope. That scope grants read **and** write; there is no read-only scope. The callback returns a `realmId`. Access tokens last about an hour.
- **Refresh tokens rotate.** Each refresh may return a new refresh token, and the latest must be saved. The token response says when it expires (Intuit announced a five-year maximum). A "Reconnect URL" is required in the app's settings.
- **Query API.** `GET /v3/company/{realmId}/query?query=select * from Invoice STARTPOSITION 1 MAXRESULTS 1000`, at most 1000 rows per page. Single records from `GET /v3/company/{realmId}/{entity}/{id}`. `include=invoiceLink` adds the invoice's online pay link.
- **Change Data Capture.** `GET /v3/company/{realmId}/cdc?entities=...&changedSince=<time>`, up to 30 days back, including deletes (`status: "Deleted"`).
- **Webhooks.** CloudEvents format: a JSON array of events with `type`, `intuitentityid`, `intuitaccountid` (realm) and `time`; ids only. Signed with `intuit-signature`: base64 HMAC-SHA256 of the raw body keyed with the verifier token.
- **Creating.** `POST /v3/company/{realmId}/invoice` and `/customer` create a record when the body has no `Id`. The same endpoints *update* when the body has `Id` and `SyncToken`, and `?operation=delete` / `?operation=void` delete or void. A `requestid` query parameter makes a create idempotent: repeating it returns the first result. `POST /v3/company/{realmId}/invoice/{id}/send?sendTo=<email>` emails an invoice.
- **Limits.** 500 requests a minute and 10 at once per company. Under Intuit's App Partner Program the free Builder tier meters "CorePlus" calls (reads, queries, reports) at 500,000 a month; creates are "Core" calls and not metered.
- **Production keys.** Need Intuit's questionnaire, public privacy policy and EULA URLs, and launch, disconnect and reconnect URLs.

### 4.2 `Gateway::QuickbooksGateway`

```ruby
class Gateway::QuickbooksGateway < Gateway
  Gateway.register(self, :accounting)
  include Accounting::Provider

  store_accessor :secrets, :client_secret, :webhook_verifier_token
  store_accessor :configuration, :client_id, :environment, :synced_entities, :customer_rollup,
                 :match_strategies, :match_field_path, :allow_create_charges, :role_labels
  store_accessor :configuration, :realm_id, :company_name, :connection_status, :last_change_check_at,
                 :last_full_sync_at, :last_error, :calls_this_month

  def fields
    [ :client_id, :client_secret, :environment, :webhook_verifier_token, :synced_entities,
      :customer_rollup, :match_strategies, :match_field_path, :allow_create_charges ]
  end

  def self.webhook_headers = [ "HTTP_INTUIT_SIGNATURE" ]
end
```

| Setting | Values | Default | Notes |
|---|---|---|---|
| `client_id`, `client_secret` | from the Intuit app | | The secret is in the encrypted `secrets` column. |
| `environment` | `sandbox`, `production` | `sandbox` | API and deep-link host. |
| `webhook_verifier_token` | from the Intuit app | | Blank: notifications refused, the changes job still runs. |
| `synced_entities` | any of `Customer`, `Invoice`, `Payment`, `CreditMemo`, `SalesReceipt`, `RefundReceipt`, `Item`, `Class`, `Department` | `Customer Invoice Payment CreditMemo Item` | Which types to copy. A rule whose roles aren't covered warns (§8.4). |
| `customer_rollup` | `none`, `parent` | `none` | §7.1. |
| `match_strategies` | ordered `reference`, `name`, `email` | `name email` | §7.2. |
| `match_field_path` | path in a Customer record, e.g. `Notes` | blank | Filled into `reference` by `normalize`. |
| `allow_create_charges` | "Let GatherPack create invoices" | off | §4.6. |
| `realm_id`, `company_name`, `connection_status`, `last_*`, `calls_this_month` | set by the system | | `connection_status`: `not_connected`, `connected`, `needs_reconnect`, `disconnected`. |

`routes`: **Connect to QuickBooks** (or **Reconnect**), **Sync now**, **Copy everything again**, **Customers**, **Records**, **Disconnect**. `finish_setup` does nothing (connecting needs a person at Intuit's sign-in page).

### 4.3 Sign-in and notifications

Routes in `config/routes/accounting.rb` (§11.9):

| Route | Action |
|---|---|
| `GET /accounting/connections/:gateway_id/connect` | Architect only. Stores a random `state` with the gateway id in the session and redirects to Intuit. |
| `GET /accounting/quickbooks/callback` | The one redirect URI. Checks `state`, exchanges the code, saves tokens and `realm_id`, fetches CompanyInfo for `company_name`, sets `connected`, queues a full sync. A different `realmId` on reconnect is refused: connect other books as a new gateway. |
| `GET /accounting/connections/:gateway_id/disconnect` | Architect only. Also Intuit's "Disconnect URL". A one-step page, "Disconnect QuickBooks?" / "Records stay; reconnect any time.", with Cancel and **Disconnect**; the GET itself changes nothing, so a link from another site can't disconnect. |
| `POST /accounting/connections/:gateway_id/disconnect` | Architect only. Revokes the token, deletes it, sets `disconnected`. Local records stay. |

The person who clicks Connect is an architect and signs in to Intuit as a QuickBooks user who may authorize apps (normally its admin). When those are different people, the architect starts the flow at the QuickBooks admin's computer (§17).

**Notifications.** `verify_webhook(payload, headers)` recomputes the HMAC with `webhook_verifier_token` and compares with `secure_compare`; refused requests never reach the job. `handle_webhook` parses the CloudEvents array, skips other realms and unsynced types, and queues `Accounting::FetchRecordJob(gateway, entity_type, external_id)` for each (a delete marks the record deleted). Where the site sits behind an access proxy, that one path needs a bypass, or the verifier token stays blank and the changes job covers it.

### 4.4 Token storage

Tokens rotate hourly, so they don't go in the gateway's `secrets` (each refresh would update the gateway, fire `gateways - update` hooks, and race with edits). New table `accounting_credentials`, prefix `acred`:

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, unique | |
| `access_token` | text | `encrypts` |
| `access_token_expires_at` | datetime | |
| `refresh_token` | text | `encrypts` |
| `refresh_token_expires_at` | datetime | Drives the "Reconnect by" warning. |
| timestamps | | |

No `CanBeHooked`, no `has_paper_trail`. Without encryption keys the gateway page says "Set the encryption keys before connecting" and Connect is disabled.

`Accounting::Quickbooks::Client#access_token` refreshes when under five minutes remain, inside `with_lock` on the credentials row after re-reading it (two jobs refreshing at once would rotate twice and lose one). A refused refresh sets `needs_reconnect`, fires `accounting - sync failed` and stops syncing. Under 30 days before `refresh_token_expires_at`, the gateway page and Account Status show admins "Reconnect QuickBooks by <date>".

### 4.5 Normalize

`Accounting::Quickbooks::Normalizer` is the only code that knows QuickBooks field names:

| Entity | `role` | Columns |
|---|---|---|
| `Customer` | `customer` | `customer_external_id` = `Id`; `parent_external_id` = `ParentRef.value`; `name` = `DisplayName`; `email` = `PrimaryEmailAddr.Address`; `reference` = value at `match_field_path`; `active` = `Active`. |
| `Invoice` | `charge` | `number` = `DocNumber`; `txn_date` = `TxnDate`; `due_on` = `DueDate`; `total_cents` = `TotalAmt`; `balance_cents` = `Balance`; `voided` when QuickBooks reports the invoice voided (it keeps the record with a zero total; confirm the marker in the sandbox); `lines` from `Line[].SalesItemLineDetail` (`ItemRef.value`, `ClassRef.value`, `Amount`), including lines inside `GroupLineDetail`; `class_ids` from `ClassRef` on the invoice and its lines; `location_ids` from `DepartmentRef`; `pay_url` from `InvoiceLink`; `public_label` "Invoice <DocNumber> · <first item name>" ("and N more" past one); `description` = `PrivateNote` and `CustomerMemo`. |
| `SalesReceipt` | `receipt` | As an invoice, with `balance_cents` 0 and label "Receipt <DocNumber>". |
| `Payment` | `payment` | `total_cents` = `TotalAmt`; `applied_to` from `Line[].LinkedTxn` where `TxnType` is `Invoice`, with each line's `Amount`; `unapplied_cents` = `UnappliedAmt`; label "Payment". |
| `CreditMemo` | `credit` | `total_cents` = `TotalAmt`; `balance_cents` and `unapplied_cents` = `Balance`; `applied_to` from the payments that apply it (QuickBooks records a credit memo's use on the Payment's `LinkedTxn` with `TxnType: CreditMemo`; the normalizer resolves those after a sync batch); label "Credit". |
| `RefundReceipt` | `refund` | `total_cents` = `TotalAmt`; label "Refund". |
| `Item` | `item` | `name` = `Name`; `active` = `Active`. |
| `Class`, `Department` | `category` | `name`. |

`external_url`: the record's page on the environment's QuickBooks host. `revision` = `SyncToken`.

### 4.6 What GatherPack may do in QuickBooks, enforced

The scope lets an app write anything, so the limits are ours, enforced in code:

- `Accounting::Quickbooks::Client` has `get`, `query`, `create_invoice`, `create_customer` and `send_invoice`. Its single HTTP method allows exactly:
  - `GET` to the API host;
  - `POST /v3/company/{realm}/invoice` and `POST /v3/company/{realm}/customer` whose JSON body has no `Id` or `SyncToken` and whose query has no `operation` (so it's a create, never an update, void or delete), always with a `requestid`;
  - `POST /v3/company/{realm}/invoice/{id}/send` for an `id` that a billing line of this gateway created;
  - `POST` to Intuit's token and revoke endpoints.
  Anything else raises before a request is sent.
- The three create/send calls also raise unless `allow_create_charges` is on.
- No code path records a payment or touches an existing record.
- The gateway page and Connect button say: "GatherPack reads your QuickBooks records. It never changes, voids or deletes anything and never records payments. With 'Let GatherPack create invoices' on, it can also create new invoices and customers, and email the invoices it created." With the setting off, the second sentence reads "Turn on 'Let GatherPack create invoices' to bill people from GatherPack."

## 5. Ledger source

### 5.1 `Gateway::LedgerSource`

For a group whose ledgers are its books. Settings (gateway edit page):

| Setting | Values | Default | Notes |
|---|---|---|---|
| `ledger_team_ids` | "Which teams' ledgers" (tick boxes, any of) | blank = every team | Ledgers outside them are ignored. |
| `charge_sign` | `negative`, `positive` | `negative` | `negative`: entries below zero are charges, above zero payments. `positive`: the reverse. |
| `credit_tag_ids` | "Tags that mean a credit" | none | Payment-side entries with one of these tags are `credit` instead of `payment` (a scholarship, say). |
| `new_ledger_team_id` | "Team for new ledgers" | blank | Where billing's customer creation (§12.5) puts a new ledger; when blank, the rule's team. |
| `role_labels` | | Charge, Payment, Credit | Editable words for `public_label`. |

`entity_types`: `{ "Ledger" => :customer, "LedgerTag" => :item, "LedgerEntry" => <by sign> }`.

### 5.2 Customers and links

Each ledger in the chosen teams is a customer (`name` = ledger name). Links come from `ledger_ownerships` whose owner is a `Person`, created with `source: ledger_owner`, and removed when the ownership goes. When a ledger's person owners include a guardian of another owner, only the ward is linked: the guardian already sees the ward's result through guardianship, and linking them would give them a bill of their own. Admins can add and remove links on the Customers page; a ledger-owner link an admin removes is remembered as a dismissal so it doesn't come back. Ledgers with no person owner appear under "Needs a link" like any customer.

### 5.3 Entries

- A split's children count; its parent counts only for the part its children don't cover yet (all of it right after Split adds two empty children), so the total always matches `Ledger#refresh_balance`. Entries with `failed: true` or `finalized: false` are skipped. That also matches `Ledger#refresh_balance`, so a ledger's balance and the rules agree.
- Ledger tags are items: `item_ids` = the entry's tag ids, `lines` = one line with the entry's amount and its first tag. `name` on `item` rows is the tag name.
- `txn_date` = the entry's `created_at` date. `due_on` is always blank: ledgers have no due dates, so rules on a ledger source rely on rule milestones (§8.3).
- `description` = `remark` (admins only). `public_label` = "Charge · <first tag>", "Payment" or "Credit".
- **Applied oldest first.** Ledger payments aren't applied to particular charges. The source treats every payment and credit as applied to the oldest unpaid charge first (by `created_at`, then id), so each charge has a defined `balance_cents` and each payment an `applied_to`. Money left after every charge is paid is that payment's `unapplied_cents`. The sync reads a whole ledger at a time and puts the computed amounts into the raw hash before `normalize` (§3.2). The ledger setup page says so: "Payments count against the oldest charges first."
- `pay_url` = the ledger's Pay page, while a `:payment` gateway exists; shown only to viewers `LedgerPolicy#pay?` allows (owners, managers, admins). `external_url` = the entry's page.

### 5.4 Keeping current

The source reads GatherPack's own tables, so changes are pushed from them, not polled. `Accounting::LedgerChanges` is a concern included from `config/initializers/accounting.rb` into `LedgerEntry`, `LedgerTagging`, `LedgerOwnership` and `Ledger` (`LedgerEntry.include(Accounting::LedgerChanges)` in `to_prepare`). Its `after_commit` (create, update, destroy) queues `Accounting::LedgerSyncJob(ledger_id)` when any ledger source covers that ledger's team. The job is limited to one at a time per ledger, re-reads that whole ledger (entries, taggings, owners), upserts, marks gone rows deleted, and queues evaluation for its linked people.

Why not the 15-minute job on `updated_at`: entries touch their ledger, but tag changes (`LedgerTagging`) and ownership changes don't, so polling would miss them, and results would lag a quarter hour behind a treasurer entering a payment while a family watches. The concern edits no upstream file. The nightly job re-reads every covered ledger as a backstop for writes that skip callbacks (`update_column`, `delete_all`).

### 5.5 Writing

`create_charge(line)`: a `LedgerEntry` on the person's linked ledger with `amount_cents` = −amount (`charge_sign: negative`) or +amount, `remark` = the run's memo, `created_by` = the person running the billing, the item tag, and `metadata: { "accounting_request_id" => line.request_id }`. Before creating, it looks for an entry with that request id and returns it if found.

`create_customer(person, ...)`: a `Ledger` named after the person, in `new_ledger_team_id` when it's set (it can be a team only admins and treasurers belong to, §5.6), else in the rule's team when the run comes from a rule with a team; with neither, the line is skipped ("No team for a new ledger: set one on the ledger source"). Its `LedgerOwnership` owner is the person only. The link is made at once with `source: created`.

### 5.6 Setup page copy

"Use your GatherPack ledgers as the books. Each ledger is a customer; ledgers owned by a person are linked to them. Charges are entries below zero, payments above. Payments count against the oldest charges first. Anyone on a ledger's team can open that team's ledgers, so keep per-member ledgers on a team only admins and treasurers belong to; the Account Status rules decide who sees each person's result."

## 6. File source

### 6.1 `Gateway::FileSource`

An admin uploads a CSV on the source's page (**Upload**, **Download template**). Columns:

| Column | Notes |
|---|---|
| `customer` | Name, email, or GatherPack id (`per_…`). The cell (trimmed, lowercased) is the customer's external id. A `per_` id or an email that's a person's account email links automatically (`source: reference`); names go through suggestions. |
| `role` | `charge`, `payment`, `credit`, `refund`, `receipt` |
| `number` | Charges: required and unique per file. Others: optional. |
| `date` | |
| `due_date` | Charges. |
| `item` | An item name; each distinct name becomes an `item` record. |
| `total` | Dollars. |
| `balance` | Charges: what's still owed. Leave blank to compute from `applied_to` rows. |
| `applied_to` | Payments, credits, refunds: charge numbers, optionally with amounts (`1042` or `1042:50.00;1043:25.00`). |
| `description` | Admins only. |

External ids: charges by `number`; other rows by `number` when present, else a hash of the row's cells. `public_label` from the role labels and the item.

### 6.2 Upload

Upload shows a **preview**: rows to add, change and remove, and row errors (unknown role, missing number on a charge, an `applied_to` number not in the file, bad amounts). **Apply** is disabled while any row has an error. Applying replaces this source's records with full-sync semantics: rows missing from the new file are marked deleted. Then evaluation runs for affected people. Capabilities: `due_dates`, `upload`; none of the live ones.

## 7. Customer links

### 7.1 `accounting_customer_links`, prefix `acl`

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | |
| `customer_external_id` | string, required | |
| `person_id` | uuid, required | |
| `source` | string | `confirmed` (an admin confirmed a suggestion), `manual` (an admin picked the person), `reference` (exact reference match, linked automatically), `ledger_owner` (§5.2), `created` (Billing created the customer, §12.5) |
| `created_by_id` | uuid, optional | |
| timestamps | | |

Unique on `(gateway_id, customer_external_id, person_id)`. `include CanBeHooked`, `has_paper_trail`.

Links are many-to-many: one customer for a family linked to each child; one person with several customers (re-created, or both customer and sub-customer). A person's records for a rule are all records whose customer is linked to them. With `customer_rollup: parent`, sub-customers of a linked customer count too; the Customers page lists them under **Linked** as "Counted with <parent>", and they don't fire `accounting - customer unlinked`.

### 7.2 Suggestions

| Strategy | Matches (neutral columns) | Confirmation |
|---|---|---|
| `reference` | The customer's `reference` equals a person's GatherPack id (`per_…`) or account email. | Exact and unique: linked automatically. Otherwise suggested. |
| `name` | `name` against the person's name, ignoring case, punctuation and accents; also "Last, First". | Confirmed by an admin. |
| `email` | `email` against account emails. When that person has wards, the wards are suggested too ("ward of <guardian> (email match)"), because a parent often receives each child's bill. | Confirmed by an admin. |

Computed when the page loads. Dismissed suggestions are kept in `accounting_customer_dismissals` (`gateway_id`, `customer_external_id`, `person_id`).

### 7.3 Customers page

Gateway page → **Customers**, admins and holders of the customer matching badge (§7.4). "Link each customer to the people it's for. Rules only see customers that are linked." Sections **Needs a link** (each unlinked active customer with suggestions, **Link** / **Not this person**, a person picker, and **Link all exact name matches**) and **Linked** (**Unlink**). Unlinking is remembered as a dismissal, whatever made the link, so an automatic link or suggestion doesn't come straight back; linking the same person by hand clears it. Inactive customers behind "Show inactive". Each customer opens its page: linked people and its records, with "Open in <source>" links when the source has `:deep_links` (admins only).

### 7.4 Customer matching badge

Setting `accounting_customer_matching_badge` (section Account Status, registered by the accounting initializer): the name of a badge only admins assign. Blank means admins only, so there is no flag beyond `feature_accounting`. It follows the forms creator badge: the name is looked up among admin-assigned badges (`Badge.added_by_admin`), and only while Badges are on, so a badge members can assign themselves, an unknown name, or Badges being off gives holders nothing.

Holders may open each source's Customers page, a customer's page and candidates, and **Link**, **Unlink**, **Not this person** and **Link all exact name matches**: `Accounting::Access.customer_matcher?(user)` backs `Accounting::SourcePolicy#customers?` and `AccountingCustomerLinkPolicy` (create, destroy, confirm_all, scope). They get nothing else: not connect, disconnect, sync, upload, Records, the gateway pages, rules, payment plans or billing. Admins are unchanged.

What a holder sees on a customer's page: the customer's name, email, reference, parent and sub-customers, linked people and suggestions, and the customer's records with their public label, date, total and balance (matching needs a person's name, email and the bills they're for). Admin-only fields stay admin-only (§3.4, §11.8): no "Open in <source>" links (`external_url`), no memos (`description`), and record names are plain text rather than links to the Records pages. A link made by a holder records them as `created_by`.

Navigation: the Account Status sidebar item shows to holders, and its page lists **Sources** with a **Customers** button per source (no Records button, no sync state, no rules unless a badge grant shows them some). Holders reach Customers there without the gateway page, which stays for architects.

## 8. Rules

### 8.1 `accounting_rules`, prefix `arl`

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | The source. |
| `name` | string, required | |
| `key` | string, unique | Generated from the name, fixed once created. |
| `description` | text | Shown to everyone who can see results. |
| `kind` | string, required | `balance`, `amount`, `count`, `custom` |
| `filters` | jsonb | §8.5 |
| `settings` | jsonb | Labels, `grace_days`, `unapplied_credit`, `measure`, `show_pay_links`, reminder settings (§10) |
| `code` | text | `custom` only; architects only. |
| `team_id` | uuid, optional | "Applies to": members of the team and its descendants get a result even with no records. |
| `read_permission` | `AudienceLevels` | Who sees a person's result. Default `admin`. |
| `amount_permission` | `AudienceLevels` | Who also sees amounts and pay links. Default `admin`. Within `read_permission`. |
| `enabled` | boolean, default true | |
| `position` | integer | |
| timestamps | | |

`include CanBeHooked`, `has_paper_trail`, `belongs_to :team, optional: true`.

### 8.2 Badge grants

`accounting_rule_badge_grants` (`rule_id`, `badge_id`, `amounts` boolean, `bill` boolean). Holders see results for the rule's people; amounts too with `amounts`; and may bill the rule's people with `bill` (§12.2). For a treasurer or mentors who aren't team managers.

### 8.3 Kinds

Each kind receives a person's matching records (§8.5) and returns `value`, `amount_cents` and `details`.

**`balance`** ("Balance remaining"). Uses `charge` rows that aren't `voided`:

- **charged** = sum of `total_cents`;
- **balance remaining** = sum of `balance_cents`. Every source lowers a charge's balance whenever anything is applied to it (a payment, a credit, a discount), so every kind of credit counts the same way;
- **paid** = charged − balance remaining.

`amount_cents` is the balance remaining. `details`: charged, paid, each charge (external id, `public_label`, date, due date, total, balance, pay link), each milestone met or not, `on_plan`, `unapplied_credit_cents`.

**Milestones** (`accounting_rule_milestones`, prefix `arm`): `rule_id`, `name`, `due_on`, `balance_at_most_cents` or `balance_at_most_percent` (0 = paid in full), `position` (in date order). Met when the balance remaining is at or below the limit (percent of charged). With no milestones, each charge's own `due_on` is a "paid in full" milestone. On a source without `:due_dates`, a rule with no milestones can never be Overdue; the rule form says so beside the milestones: "Nobody will ever be Overdue: this source has no due dates. Add a milestone."

A person with a payment plan (§8.4) uses the plan's milestones instead.

| Value | When | Default label |
|---|---|---|
| `not_invoiced` | No matching charges. | Not invoiced |
| `paid` | Balance remaining is zero. | Paid |
| `overdue` | A milestone whose `due_on` + `grace_days` has passed isn't met. | Overdue |
| `partial` | Not overdue, something paid, a balance remains. | Partly paid |
| `unpaid` | Not overdue, nothing paid. | Not yet paid |

Checked in that order. Labels renamable per rule. Screens name the missed milestone ("Overdue: Deposit"), and to viewers who may see amounts, the catch-up ("$150 to meet Deposit"); on schedule, the next one ("Next: $300 by Mar 1").

**Credit not applied to a charge.** The linked customers' `payment` and `credit` rows' `unapplied_cents` go into `details.unapplied_credit_cents`. The rule's `unapplied_credit` setting:

- `show` (default): the balance follows the charges only. The profile tab and statement say "A payment of $X is waiting to be applied" to viewers who may see amounts; the rule page gives admins an "Unapplied credit" mark and filter (a to-apply work list).
- `count`: subtracted from this rule's balance before milestones. For groups where a person only ever has one kind of charge; the form says so.

**`amount`.** `settings.measure` is `invoiced` (`charge` and `receipt` totals) or `paid` (`payment` and `receipt` totals minus `refund` totals). With `filters.items`, `invoiced` sums only matching `lines`, and `paid` sums the `applied_to` amounts on matching charges.

**`count`.** The number of matching records, e.g. receipts this year.

**`custom`.** Architect Ruby, run like `Hook#run`. Sees `person`, `rule`, `records` (matching `AccountingRecord` scope; may read `data`), `customers`. Returns `{ value:, amount_cents:, details: }` or a string. An exception stores `value: "error"`, shown to admins only, no actions.

### 8.4 Payment plans

An admin can give one person their own milestones for a rule. `accounting_person_milestones`, prefix `apm`:

| Column | Type | Notes |
|---|---|---|
| `rule_id` | uuid, required | |
| `person_id` | uuid, required | |
| `name` | string, required | "First payment" |
| `due_on` | date, required | |
| `balance_at_most_cents` / `balance_at_most_percent` | | One of the two, as rule milestones. |
| `position` | integer | |
| `note` | text | Admin only ("Agreed with the family by phone"). |
| `created_by_id` | uuid | |
| timestamps | | |

`include CanBeHooked`, `has_paper_trail`. Any plan rows for a person replace all of the rule's milestones for that person; removing the last row returns them to the rule's.

- **Visibility.** The plan's milestones (names, dates, amounts) show to the person, their guardians and admins, subject to the rule's `amount_permission` for amounts. On a rule with any payment plan, everyone but admins sees only the status for everyone on the rule ("On schedule" or "Overdue", no milestone names, dates or amounts), whether or not that person is on a plan, because a plan can reveal hardship and a plain line beside others' named milestones would give it away. The one exception: the person and their guardians still see the person's own milestone line and plan. Rules without plans show milestone names as usual. Nobody but admins sees that a person is on a plan or the note.
- **Where.** Admins: the person's Account tab, on the rule's row, **Payment plan** (an edit page with milestone rows, Cancel, Save, and **Remove plan** under More).
- **Rule page.** An admin-only **On a plan** filter and mark.
- **Duplicate** (§11.3) never copies plans.

### 8.5 Filters

`filters` jsonb, all optional, combined with AND:

| Key | Meaning (neutral columns) |
|---|---|
| `roles` | Narrows the roles a kind uses, e.g. only `receipt` for `amount`. |
| `items` | Item ids; a record matches when `item_ids` overlaps. |
| `classes` | `class_ids` overlaps. |
| `locations` | `location_ids` overlaps. |
| `txn_date_from`, `txn_date_to` | `txn_date`, inclusive. |
| `due_date_from`, `due_date_to` | `due_on`. |
| `min_total` | Skip records whose `total_cents` is below it. |

The form shows items, categories and locations as tick boxes by `name` from `item` / `category` rows ("Any of these"). Stored values are ids, so renames don't break rules. A rule that needs a role its source doesn't copy (`synced_entities`) warns and isn't evaluated.

### 8.6 `accounting_rule_results`, prefix `arr`

`rule_id`, `person_id`, `value`, `amount_cents`, `details`, `evaluated_at`, `changed_at`, `badge_assignment_id`. Unique on `(rule_id, person_id)`. No `CanBeHooked` (the domain event is the signal). `Person#accounting_result(key)` helps Reports and widgets.

### 8.7 Evaluation

`Accounting::EvaluateRuleJob(rule, person_ids = nil)` recomputes and saves only changes. It runs after each sync or upload for affected people; when links change; when a rule, a rule milestone or a payment plan is saved, or on **Evaluate now**; and nightly for everyone (milestones pass without records changing). Who: people linked to any customer of the rule's source, plus members of `team_id` and its descendants. A person who no longer qualifies loses their result and the rule's actions undo.

## 9. Actions

`accounting_rule_actions`, prefix `ara`: `rule_id`, `action` (`badge`, `person_field`), `condition` (`{ "values": [...] }` or `{ "op":, "amount_cents": }` / `{ "op":, "count": }`; blank = always), `badge_id`, `person_field_id`, `write` (`label`, `value`, `amount`).

One badge action per rule. Two turned-on rules can't fill in the same person field (saving names the other rule); the same badge on two rules is allowed, with a warning, and each rule takes back only what it gave.

**Taking back.** Turning a rule off takes back what its actions gave, in a job that waits for any evaluation of that rule already running; results are kept, and turning it back on gives them again on the next evaluation. Deleting a rule (or its source) always takes them back. Either way, only the badge assignment a result records is removed, and a field is cleared only while it still holds the value the rule last wrote (recorded on the result) and no other turned-on rule fills that field for that person. While badges or person fields are off, those actions are skipped, not undone. Removing a badge action takes its badges back on the next run; removing a field action leaves the values it wrote.

### 9.1 Badge

Only badges admins assign are offered. The person has the badge while the condition holds. The rule creates the assignment, records it in `badge_assignment_id`, and removes only that one. Hand-made assignments are never removed; a team badge skips non-members (noted in `details`).

### 9.2 Person field

Writes the label, value or amount, or clears it, with `acting` unset, so `person_fields - value changed` fires. The form warns when the field's `write_permission` isn't `admin`. The rule's own Account tab already shows results under the rule's permissions; a field exists for other features to test.

## 10. Reminders

**Choice: native reminders on the rule.** Checklist reminders (`feature/checklists-reminders`) go on a checklist's schedule: every N days, and N days before the checklist ends. They can't remind N days before each of a rule's milestones, which differ per person once payment plans exist (§8.4), and they can't hold back amounts from recipients who may see the status but not the money. So the rule sends its own, built the same way checklist reminders are (one email per recipient a day, the same three "what it may say" levels, summaries and phone notifications when those seams are merged), and the checklist reminder code is not a dependency.

Settings on the rule form's **Reminders** part:

| Setting | Default | Notes |
|---|---|---|
| "Remind N days before each milestone" | blank (off) | People not meeting that milestone yet. |
| "Then, while overdue, remind every N days" | blank (off) | |
| "Send to" | The person and their guardians | Choices: the person; their guardians; both. A recipient must meet the rule's `read_permission` for the person, so guardians get nothing on a rule whose level excludes guardians. |
| "What reminders may say" | Name and status | `everything`: name, status, milestone, catch-up amount and pay link; `name_only`: rule name, status and milestone name and date; `sign_in`: "You have an account update. Sign in to see it." |

Amounts and pay links go only to recipients who meet `amount_permission`, whatever the setting; anyone else gets the `name_only` form. A person on a plan is reminded before the plan's milestones; a leader is never a recipient. Text uses `public_label` only (§11.8).

`Accounting::ReminderJob`, daily (`config/recurring.d/accounting.yml`), gathers every due reminder across rules and sends one `AccountingMailer.reminder` per recipient. `accounting_reminders` (prefix `arem`: `rule_id`, `person_id`, `recipient_id`, `milestone_key` (rule or plan milestone id, or `overdue`), `sent_at`) keeps a reminder from going twice and spaces overdue ones. When `feature/digests` is merged, the feature registers a `:accounting` summary section (`delivery` from the Account Status setup setting "Account reminders: An email each time / In the daily digest", default each) and honours each person's own choice through `delivery_for`; when phone notifications are merged, it registers an `:accounting` push topic. Both behind `defined?` guards.

The rule page shows admins "Reminders: 3 days before each milestone, then every 7 days while overdue; last sent Mar 1".

## 11. Screens

### 11.1 Navigation

```ruby
GatherPack::Features.register(
  GatherPack::Feature.new(
    key: :accounting,
    label: "Accounting",
    description: "Account status, reminders and billing from your books or ledgers",
    default_enabled: false,
    nav_section: "Finance",
    nav_items: [ GatherPack::Feature::NavItem.new(label: "Account Status", path: :accounting_rules_path, icon: "file-invoice-dollar",
                                                  visible: ->(user) { Accounting::Access.sees_any_rule?(user) }) ],
    profile_tabs: [ GatherPack::Feature::ProfileTab.new(label: "Account", path: ->(person) { person_accounting_path(person) },
                                                        visible: ->(user, person) { Accounting::Access.sees_any_result?(user, person) }) ]
  )
)
```

Sources stay under Setup → Gateways with the other gateways. A Setup page section **Account Status** holds the feature-wide settings (reminder delivery).

### 11.2 Account Status list (`/accounting/rules`)

Header card: "Account Status", "What each person owes and whether they're on schedule." Each enabled rule the viewer sees results for, with:

- counts per value among people the viewer can see ("Paid 41 · Partly paid 3 · Overdue 6 · Not invoiced 2");
- **treasurer totals**: charged, collected (paid) and balance remaining, summed over the people whose amounts the viewer may see (`amount_permission`), with "of 52 people" when that's fewer than they can see. Hidden when it's nobody.

Admins also see disabled rules, each source's connection state and last sync, the reconnect warning, and **Billing runs** (§12).

### 11.3 Rule page

Header card: name, description, source, the same counts and totals as the list (plus unapplied credit total for admins), and the reminders line. Filter bar: value, team, and for admins **Unapplied credit** and **On a plan**. Table (people the viewer can see): name, team, value (colored), amount (if permitted), "changed on", "Open in <source>" for admins with `:deep_links`; Columns chooser, Print, Download CSV at the bar's right. The CSV for non-admins carries `public_label` text only.

Action row: **Edit**, **Bill people** (admins and `bill` grant holders; §12), then **More**: **Evaluate now**, **Duplicate**, **Delete**.

**Duplicate** sets up next season: the copy moves the years in its name on ("2026-27 Dues" → "2027-28 Dues"), moves date filters and milestone dates on a year, keeps filters, milestones, visibility, actions and reminder settings, starts disabled and opens on Edit. Results, payment plans, reminder history and billing runs are never copied.

**Rule form** (admins; `code` and `kind: custom` architects only), link tabs: **Question** (name, description, source, kind and its options, milestones, labels), **Records** (filters), **People** (applies to, result level, amount level, badge grants), **Reminders**, **Actions**, **Enabled**. Directions: "A rule answers one question from your money records for each person, like 'Are their dues paid?'. Pick which records count, who it's for, and who can see the answer." **Preview** evaluates the unsaved rule for five linked people. Choices a source can't support are hidden ("Show pay links" without `:pay_links`).

### 11.4 Account tab

A profile tab, **Account**, shown when the viewer can see at least one rule's result for this person. Per rule:

- name, value, "as of" time; the milestone line (§8.3), or for a person on a plan, the plan's milestones to those who may see them (§8.4);
- amount, charges (by `public_label`) and **Pay online** when the viewer meets `amount_permission`, `show_pay_links` is on and the source has `:pay_links`;
- the "waiting to be applied" line;
- for admins: **Payment plan**.

Below: **Statement** when the viewer meets `amount_permission` for any rule; for admins, linked customers and **Manage links**. Guardians see it on a ward's profile, which they can already open.

### 11.5 Statement (`/people/:id/accounting/statement`)

One table, newest first: the charges matched by rules whose amounts the viewer may see, the payments, credits and refunds whose `applied_to` names those charges (with the applied amount), and the linked customers' unapplied payments and credits. Columns: date, what it is (`public_label`), charge, payment, running balance; current balance at the top. Admins see every record of the linked customers, a `description` column and "Open in <source>" links. Read-only, shared print layout.

### 11.6 My GatherPack (connector branch)

On `feature/my-gatherpack-accounting` (§16.1):

- **Home: an Account section**, `MyGatherpack.register_section(:accounting, partial: "my_gatherpack/accounting", column: :side, position: 22)`, enabled while both features are on. One row per person the viewer sees results for among themselves and their wards: name (wards only), each visible rule's status, balance remaining (if amounts are visible), next milestone, and **Pay online** as the row's one solid button when allowed. Renders nothing when there are no rows.
- **Family page: a row per ward**, one `render "accounting/family_rows", ward: card.ward` line in `family/_ward_card.html.erb` (a fork file from `feature/my-gatherpack-family`), showing the same line for that ward under their forms and checklists.

Text follows §11.8.

### 11.7 Records (admins)

Gateway page → **Records**: the copy, filterable by role, customer and date; each shows its neutral columns, raw JSON, and "Open in <source>". No editing.

### 11.8 Credit privacy

Non-admins only ever see `public_label` and amounts: "Payment", "Credit", "Refund", "Invoice 1042 · Dues". Memos, remarks, private notes, credit reasons and payment-plan notes are admin-only (`description`, `note`). A scholarship or hardship credit appears as "Credit" (§4.5, §5.3: credit labels never include an item). This holds on the statement, the Account tab, the Home section and Family page, the rule page's CSV for non-admins, reminders and summaries, and any later MCP tool over these tables.

### 11.9 Routes (`config/routes/accounting.rb`)

```ruby
namespace :accounting do
  get "quickbooks/callback", to: "quickbooks_connections#callback"
  resources :connections, only: [] do
    get :connect, :disconnect, on: :member, controller: "quickbooks_connections"
    post :disconnect, on: :member, controller: "quickbooks_connections", action: :revoke
    post :sync, :full_sync, on: :member, controller: "syncs"
    resources :uploads, only: %i[ new create show ] do
      post :apply, on: :member
      get :template, on: :collection
    end
    resources :customers, only: %i[ index show ]
    resources :records, only: %i[ index show ]
  end
  resources :customer_links, only: %i[ create destroy ] do
    post :confirm_all, on: :collection
  end
  resources :customer_dismissals, only: :create   # Not this person
  resources :rules do
    post :evaluate, :duplicate, on: :member
    get :export, on: :member
    resources :payment_plans, only: %i[ edit update destroy ], param: :person_id
    resources :billing_runs, only: %i[ new create ]
  end
  resources :billing_runs, only: %i[ index new create show ] do
    post :retry_failed, on: :member   # saving a run starts it
    get :export, on: :member
  end
end
scope "people/:person_id", as: :person do
  get "accounting", to: "accounting/people#show", as: :accounting
  get "accounting/statement", to: "accounting/statements#show", as: :accounting_statement
end
```

Always drawn; controllers refuse with "Accounting is turned off" when the flag is off.

## 12. Billing

The group today creates every dues bill by hand in its accounting system. Billing lets GatherPack create them, built after the read side.

### 12.1 Principles

- **The source stays the record.** GatherPack authors charges and writes them into the source; they come back through normal sync like any other record, and only then count.
- GatherPack still never edits, voids or deletes anything in the books, and never records payments.
- Nothing is written without the source's `:create_charges` capability; on QuickBooks that needs "Let GatherPack create invoices" on (§4.6).

### 12.2 Who may bill

Admins, from a rule or from Account Status. Holders of a rule badge grant with `bill` on, from that rule's page only, for that rule's people, with the item limited to the rule's `items` filter. Billing runs list and pages: admins, and the person who ran it.

### 12.3 Model

`accounting_billing_runs`, prefix `abr`:

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | |
| `rule_id` | uuid, optional | When started from a rule. |
| `created_by_id` | uuid, required | |
| `item_external_id` | string, required | |
| `amount_cents` | bigint, required | Default per person. |
| `txn_date`, `due_on` | date | `due_on` hidden without `:due_dates`. |
| `memo` | text | Printed on the charge where the source supports it. |
| `create_customers` | boolean | "Create a customer for people who don't have one". |
| `send_from_source` | boolean | "Email the invoices from <source>". |
| `status` | string | `draft`, `running`, `finished` |
| `finished_at` | datetime | |
| timestamps | | |

`accounting_billing_lines`, prefix `abl`: `run_id`, `person_id`, `customer_external_id`, `amount_cents`, `status` (`pending`, `created`, `failed`, `skipped`, `exported`), `request_id` (uuid, set when the line is made), `external_id`, `error`, `sent_at`. Unique on `(run_id, person_id)`.

Runs `include CanBeHooked`; lines only fire the failed event (§14). Both have `has_paper_trail`.

### 12.4 Screen: Bill people

Reached from a rule's **Bill people** ("Bill people who aren't invoiced": who starts as the rule's people with status Not invoiced) or from Account Status → Billing runs → **New billing run**. An edit page:

- **What**: item (a select of active `item` rows), amount, invoice date, due date, memo.
- **Who**: a team; the rule's people with status Not invoiced; or picked people (search and add).
- **More choices**: "Create a customer for people who don't have one" (with `:create_customers`), "Email the invoices from <source>" (with `:send_charges`).
- **Preview** shows one row per person: name, customer (a select when they have several linked; default the one with the latest charge), amount (editable override), and a tick box to include. Rows with a warning start unticked: "Already billed: Invoice 1042" (a non-deleted charge matching the rule's filters, or this item since the invoice date when no rule), "No customer: will be created" or "No customer: will be skipped".
- Cancel, **Create invoices** ("Create 38 invoices in QuickBooks?" inline confirm above it). On a source without `:create_charges`, the button is **Download CSV** (§12.6).

### 12.5 The job

`Accounting::BillingRunJob(run)` (one at a time per gateway) works through `pending` lines:

1. Locks the line; skips anything not `pending`. A `created` line is never re-sent.
2. No customer: with `create_customers` and `:create_customers`, `create_customer(person, email:, request_id:)` (email: the first guardian's account email when the person has guardians, else the person's), then a link with `source: created`. Otherwise `skipped` with the reason.
3. `create_charge(line)` with the line's `request_id`; stores `external_id`, sets `created`. QuickBooks passes `request_id` as `requestid`; the ledger source looks it up in entry metadata. A retry after a crash therefore returns the first charge instead of a second.
4. With `send_from_source`, `send_charge(external_id, email:)`; sets `sent_at`.
5. Errors: `failed` with the message; fires `accounting_billing_lines - failed`. 429 and 5xx retry with backoff first.
6. Queues a fetch (QuickBooks) or ledger sync for the new charges, so they show without waiting for the changes job.

When no lines are `pending`, the run is `finished` and fires `accounting_billing_runs - finished`. The run page lists lines by status with errors, and **Retry failed** (sets failed lines back to `pending` with the same `request_id`).

### 12.6 File source

No live create. **Download CSV** produces the charges in the file source's template layout (one `charge` row per line, numbers left blank for the accounting program to assign) to import there; lines become `exported`. The next upload brings them back.

## 13. Sync

### 13.1 Jobs

All sync jobs for one gateway run one at a time (`limits_concurrency to: 1, key: gateway.id`).

| Job | Sources | What it does |
|---|---|---|
| `Accounting::FullSyncJob(gateway)` | all but file | For each entity type: `each_record`, `normalize`, upsert (skip unchanged `revision`), mark records not seen deleted. QuickBooks customers include inactive ones. Then evaluation. |
| `Accounting::ChangesJob(gateway)` | `:change_feed` | `each_change` since `last_change_check_at`; past `change_window`, a full sync instead. |
| `Accounting::FetchRecordJob(gateway, type, id)` | `:notifications` | One record. |
| `Accounting::LedgerSyncJob(ledger_id)` | ledgers | §5.4. |
| `Accounting::ApplyUploadJob(upload)` | file | §6.2. |
| `Accounting::EvaluateRuleJob(rule, ids)` | — | §8.7. |
| `Accounting::ReminderJob` | — | §10. |
| `Accounting::BillingRunJob(run)` | — | §12.5. |

### 13.2 Schedule (`config/recurring.d/accounting.yml`)

```yaml
accounting_changes:
  class: Accounting::ScheduleChangesJob   # ChangesJob for each source with :change_feed
  queue: default
  schedule: every 15 minutes
accounting_nightly:
  class: Accounting::NightlyJob          # weekly full sync (Sundays), nightly ledger re-read, nightly evaluation
  queue: default
  schedule: at 3am every day
accounting_reminders:
  class: Accounting::ReminderJob
  queue: default
  schedule: at 8am every day
```

All do nothing while the feature is off.

### 13.3 Failures and call budget

401 after a refresh: `needs_reconnect`. 429 or 5xx: retry with backoff, up to 5 attempts. Anything else: `last_error`, `accounting - sync failed`, previous data left in place; results never go blank because a sync failed. Account Status shows admins "Last synced … ago" in red past a day.

QuickBooks at team scale (about 500 customers, 1,000 transactions a year): full sync about 10 calls, changes job 96 a day, one fetch per notification. A busy month is under 5,000 metered calls, about 1% of the Builder tier. Billing's creates are unmetered Core calls. The gateway page shows the month's count.

## 14. Hooks

Record events (`GatherPack::HookCatalog.register_targets` in the initializer):

| Table | Why |
|---|---|
| `accounting_records` | React to any change, e.g. post to a channel when a large payment arrives. Fires only when `revision` changed. |
| `accounting_customer_links` | Audit or notify when someone links a person. |
| `accounting_rules` | Someone changed what a rule answers or who sees it. |
| `accounting_person_milestones` | A payment plan was set up or changed (the hook's code sees the note; architect code already sees everything). |
| `accounting_billing_runs` | A run was started. |

Domain events (`register_events`):

- **`accounting_rules - result changed`**: `model` is an `AccountingRuleChange` (`rule`, `person`, `old_value`, `new_value`, `old_amount_cents`, `new_amount_cents`, `unapplied_credit_cents`, `on_plan`). Fired after the result is saved and actions ran.
- **`accounting - sync failed`**: `model` is the gateway.
- **`accounting - customer unlinked`**: `model` is the new `customer` record when no automatic link was made.
- **`accounting_billing_runs - finished`**: `model` is the run (counts by status in `details`).
- **`accounting_billing_lines - failed`**: `model` is the line, with `error`.

Not hookable: `accounting_rule_results` (the result-changed event covers it), `accounting_credentials` (secrets), `accounting_reminders` (a send log), `accounting_billing_lines` record events (the failed event covers what matters), `accounting_customer_dismissals`, `accounting_rule_badge_grants`, `accounting_rule_actions`, `accounting_rule_milestones` (settings rows; changes show in the audit log through their rule).

Hook and custom-rule code runs with full access to every record, including amounts and private notes a page's viewer may not see. That's the existing contract for architect code, restated in the code fields' directions.

## 15. Tests (Minitest)

No WebMock. `Accounting::Quickbooks::Client` takes a transport; tests pass a fake that returns recorded sandbox fixtures (`test/fixtures/files/quickbooks/*.json`) and records requests.

- **Provider contract.** `Accounting::ProviderContract`, included in each source's test: fixtures normalize to the expected columns; `public_label` never contains a description; undeclared capabilities raise; `create_charge` twice with one request id makes one charge.
- **Layering.** No QuickBooks field name appears outside `app/models/accounting/quickbooks/` and `app/models/gateway/quickbooks_gateway.rb`; rule code never reads `data` except in `custom`.
- **QuickBooks client:** GET to the API host allowed; POST create invoice and customer allowed only with no `Id`/`SyncToken`/`operation` and with a `requestid`; send allowed only for an invoice a billing line created; token and revoke allowed; every other method, path or body raises; create/send raise with `allow_create_charges` off; refresh near expiry; rotated refresh token saved; concurrent refreshes make one call; a refused refresh sets `needs_reconnect`.
- **QuickBooks normalize:** invoices with group lines; classes on line vs invoice; voided; payment `applied_to` and `UnappliedAmt`; credit memo balance; sales receipt; refund; pay link; deep link.
- **Webhook:** valid signature accepted and fetches queued; bad signature refused by `verify_webhook`; other realms and unsynced types ignored; deletes mark deleted.
- **Ledger source:** each ledger is a customer; person owners linked as `ledger_owner`, a guardian co-owner not linked; removing an ownership removes its link; an admin-removed link stays removed; `charge_sign` both ways; credit tags; split parents skipped and children counted; failed and unfinalized skipped; balance equals `Ledger#refresh_balance` sign-adjusted; oldest-first application gives each charge's balance, `applied_to` and leftover `unapplied_cents`; an entry, tagging or ownership change queues `LedgerSyncJob`; ledgers outside the chosen teams ignored; `create_charge` sign and request-id reuse; `create_customer` team choice and skip.
- **File source:** template columns; preview row errors block Apply; `per_` id and email link automatically; balance from `applied_to`; a row missing from the next file is marked deleted; billing exports rows in the template layout.
- **Sync:** full sync pages past 1,000 and marks missing deleted; changes job advances and falls back past 30 days; unchanged `revision` doesn't save or fire hooks.
- **Links:** each strategy on neutral columns, including email → wards; exact reference links automatically; dismissals stick; parent rollup.
- **Kinds:** each `balance` value and order; credits lower the balance like payments; milestones by amount and percent; next-milestone and catch-up; no milestones uses `due_on`; no milestones and no `:due_dates` never overdue, with the form warning; voided skipped; grace days; unapplied credit `show` and `count`; `amount` with items; `custom` shapes and errors. The same `balance` cases pass on all three sources.
- **Filters:** item, class and location overlap; date bounds inclusive; `min_total`.
- **Payment plans:** a plan replaces rule milestones for that person only; removing it restores them; person, guardian and admin see plan milestones; a leader and a grant holder see status only; "On a plan" filter admin-only; the note admin-only; Duplicate doesn't copy plans.
- **Reminders:** sent N days before a milestone only to people not meeting it; overdue cadence; guardians only when `read_permission` includes them; amounts only to recipients meeting `amount_permission`, else the name-only form; `sign_in` says nothing; one email per recipient a day; no repeat for the same milestone; plan milestones used for a person on a plan; leaders never recipients; with digests merged, `delivery_for` respected.
- **Totals:** counts over visible people; amounts summed only over people whose amounts the viewer may see; hidden when none.
- **Family and Home:** a guardian sees each ward's visible rules, balances only when permitted, pay link only when allowed; a former guardian sees nothing; nothing renders without rows.
- **Credit privacy:** a credit with a scholarship memo shows as "Credit" on the statement, Account tab, Home, Family, non-admin CSV and reminder; admins see the memo.
- **Actions:** badge added and removed; hand-made assignment kept; team badge skips non-members; person field written and cleared.
- **Permissions:** results and amounts at each level for subject, guardian, leader, teammate, stranger; badge grants (`amounts`, `bill`); `amount_permission` ⊆ `read_permission`; non-architects can't set `code`; Account tab hidden when no rule is visible; statement shows only permitted records.
- **Billing:** preview's Not invoiced population; already-billed rows start unticked; overrides and exclusions; one charge per line; a crash between create and save doesn't double-bill (same request id); created lines never re-sent; customer creation with guardian email; skipped without `:create_customers`; send only with `:send_charges`; grant holders limited to the rule's people and items; non-billers refused; failed lines retried with the same request id; hooks fire; a source without `:create_charges` exports CSV; Duplicate copies no runs.
- **Hooks:** each catalog entry fires with the right model; no result-changed event when the value is unchanged.
- **Feature off:** routes refuse; tab, nav, Home section and ward rows don't render; recurring jobs and ledger callbacks do nothing.

Manual, against the Intuit sandbox before production keys: connect, disconnect, reconnect; "send test event"; a sandbox payment turning a result to `paid` within a minute with notifications or 15 without; a billing run creating, emailing and syncing back two invoices.

## 16. Fork strategy

### 16.1 Branches

- **`feature/accounting`**, based on `feature/person-fields` (declared dependency), placed in `fork/features.txt` after its dependencies: `feature/person-fields` (audiences, guardianship, person fields), `feature/security-series` (gateway `secrets`, `verify_webhook`, encryption initializer), `feature/extension-registries` (`HookCatalog`), `feature/recurring-routes-seams` (route and recurring files), `feature/profile-tabs` (the Account tab), `feature/screen-kit`. Uses `feature/digests` and phone notifications only when present (`defined?`).
- **`feature/my-gatherpack-accounting`**: the Home section and Family ward rows (§11.6). Depends on `feature/accounting` and `feature/my-gatherpack-family`; placed after both.

**Naming.** Upstream-style (`Accounting::`, `accounting_*`, `Gateway::LedgerSource`), nothing group-specific. **Flag.** `:accounting` in `GatherPack::Features`, default off; the connector branch follows both flags.

### 16.2 Upstream files touched (for `FORK.md`)

| File | Change |
|---|---|
| `db/schema.rb` | New tables and the version line (regenerated). |
| `app/views/gateways/_form.html.erb` | 4 lines: for each field, render the fork partial `gateways/_field_input` when `@gateway.try(:field_input, field)` returns tick boxes or a choice; otherwise the unchanged input. Gives the ledger source's team and tag tick boxes and the QuickBooks "Let GatherPack create invoices" choice. `Gateway#field_input` comes from a concern included from the initializer. |

Everything else is new files or seams: the initializer (feature registration, `HookCatalog`, `LedgerEntry.include(Accounting::LedgerChanges)` and the same for `LedgerTagging`, `LedgerOwnership`, `Ledger`), `config/routes/accounting.rb`, `config/recurring.d/accounting.yml`, models, jobs, controllers, policies, views, mailer, tests and fixtures. The connector branch edits one fork file, `app/views/family/_ward_card.html.erb` (one `render` line), as `feature/my-gatherpack-activity` does.

### 16.3 Migrations

One per table, all reversible:

- `accounting_credentials`
- `accounting_records` (with the neutral columns and their indexes)
- `accounting_customer_links`
- `accounting_customer_dismissals`
- `accounting_rules`
- `accounting_rule_milestones`
- `accounting_rule_badge_grants` (with `amounts` and `bill`)
- `accounting_rule_actions`
- `accounting_rule_results`
- `accounting_person_milestones`
- `accounting_reminders`
- `accounting_uploads` (file source: the file, its preview and who applied it)
- `accounting_billing_runs`
- `accounting_billing_lines`

### 16.4 Rollout order

1. **Read side, QuickBooks:** the provider interface, plain records, QuickBooks source (connection, credentials, client, normalize, full sync, changes job, notifications), Records page. Against the Intuit sandbox.
2. **Links:** customer links and the Customers page.
3. **Rules and statuses:** kinds, milestones, results, Account Status pages, the Account tab and statement, credit privacy.
4. **Actions and Hooks.**
5. **Ledger and file sources.**
6. **Payment plans, reminders, the My GatherPack connector branch, treasurer totals.**
7. **Billing:** QuickBooks writes (allowlist, setting, copy), ledger and file billing, runs and lines.

Each step ships with the feature off. A group turns it on after a comparison against the treasurer's own aging report on staging matches.

### 16.5 Worked examples (configuration, not code)

**A club on QuickBooks.** Each member is their own customer with their own invoice, siblings included; parents receive their children's invoices; members pay through a platform that pays out in bulk and the treasurer applies the money by hand.

| Setting | Value |
|---|---|
| `match_strategies` | `name email` (email finds the parent and suggests the wards). |
| `customer_rollup` | `none` |
| Rule | `balance`, items = the dues product, transaction dates within the season, applies to the members' team, `unapplied_credit: show`. |
| Milestones | "Deposit": balance at most 50% by the first date. "Paid in full": 0 by the second. |
| Visibility | `read_permission` and `amount_permission`: `family`; pay links on. |
| Reminders | 5 days before each milestone, then every 7 days while overdue; to the member and guardians; "Everything". |
| Plans | One family pays in four parts on their own dates. |
| Actions | `person_field`, always, `write: label`, into a hidden admin-written "Dues" select field read at `family`, which an eligibility checklist item tests ("is any of Paid"). |
| Billing | With "Let GatherPack create invoices" on, the treasurer opens the rule after the roster settles, **Bill people** (Not invoiced), dues product, the season amount, due date = the deposit date, "Email the invoices from QuickBooks". |

**A troop on ledgers.** A group that keeps a ledger per member on an admin-only team: ledger source with `charge_sign: negative`, a "Scholarship" tag as a credit tag; a `balance` rule filtered on the "Dues" tag with "Half by" and "All by" milestones (no due dates on ledgers); results visible to `family`. **Bill people** adds the dues charge to each member's ledger, creating a ledger for new members in the rule's team.

### 16.6 Intuit setup checklist

1. Create the Intuit developer account with a group-owned email address, so the app outlives any one volunteer.
2. Create the app with scope Accounting; note the sandbox company.
3. Redirect URIs: `http://localhost:3000/accounting/quickbooks/callback` (development) and each deployment's `https://…/accounting/quickbooks/callback`.
4. Webhooks: `https://<host>/gateways/<gateway id>/webhook`, CloudEvents, entities Customer, Invoice, Payment, CreditMemo, Item. Copy the verifier token into the gateway; add the access-proxy bypass for that path.
5. Production keys: the questionnaire, privacy policy and EULA pages, and the launch (gateway page), disconnect and reconnect URLs.
6. Encryption keys present in each deployment (they are wherever gateway secrets already work).

## 17. Decisions

1. **Layers.** Sources and rules are separate; rules read only neutral columns. A test enforces it (§3.1, §15).
2. **Neutral columns on `accounting_records`**, not a sibling table: one-to-one, written together, read by every query (§3.4).
3. **Names in the UI.** "Account Status" for the nav link, "rules" for the questions, "Account" for the profile tab. ("Checks" reads as paper checks on a finance screen.)
4. **Who manages sources, links and rules:** admins (connecting QuickBooks: architects). Treasurers who aren't admins get a badge grant with `amounts`, and `bill` to bill. A treasurer who isn't an admin can also match customers through the customer matching badge (§7.4).
5. **Partial payments** are configuration: milestones, plus whatever tests the result.
6. **Who clicks Connect:** an architect, at the QuickBooks admin's browser when they're different people.
7. **Ledger source keeps current by `after_commit` from an included concern**, with a nightly re-read; no upstream file edited (§5.4).
8. **Ledger payments apply oldest charge first** (§5.3).
9. **A guardian who co-owns a ward's ledger isn't linked to it** (§5.2).
10. **Native reminders** rather than checklist reminders, because milestones differ per person and amounts must be held back by recipient (§10).
11. **Payment plans replace the rule's milestones entirely** for that person, and leaders see only the status (§8.4).
12. **Family view on Home and the Family page** through a connector branch, using the existing section registry and one line in a fork view (§11.6).
13. **Billing writes only creates**, idempotent by request id; QuickBooks writing is off until a setting is on; the client enforces the exact allowlist (§4.6, §12).
14. **Ledger customer creation** goes in the source's "Team for new ledgers" when set, else the rule's team, else skipped (§5.5).
15. **Billing email** for a new customer is the first guardian's when the person has guardians (§12.5).
16. **Already-billed people start unticked** in a billing preview (§12.4).
17. **The `amount`, `count` and `custom` kinds stay.**
18. **Upstream:** not planned; only the owner raises it.
