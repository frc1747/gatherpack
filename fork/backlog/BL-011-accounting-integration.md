# BL-011: Accounting integration (QuickBooks Online first)

| | |
|---|---|
| Kind | fork-only feature (built with upstream naming, so it could be offered later; Corey decides) |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-07 |
| Planned branch | `feature/accounting`, based on `feature/person-fields` (declared dependency) |
| Upstream issue / PR | none |

Spec rev. 1, 2026-10-07. Written against `hbr/platform` 56b8ccf and `feature/person-fields` 2d77442. Nothing is built yet.

## 1. Goal

Let GatherPack answer questions about people from the organization's accounting system, starting with QuickBooks Online (QBO). The first question is "has this person's invoice been paid, or is it behind?" It must not be the only one, and nothing about HBR's dues may be written into code.

The feature is a framework with four layers. Each layer is generic. What an organization wants is set up as configuration:

1. **Connection.** Connect a QBO company, keep its sign-in fresh, and keep a local copy of the records we're told to copy.
2. **Local copy.** The raw accounting records (customers, invoices, payments, products/services, ...) stored as JSON, kept current by notifications and a regular catch-up.
3. **Customer links.** Which GatherPack person (or people) each accounting customer represents, suggested automatically and confirmed by an admin.
4. **Rules.** Saved questions ("2027 Membership Dues", "Travel fee", "Total given this year"), each producing one result per person. A rule says who may see its results, and what happens when a result changes (add a badge, write a profile field, fire a hook).

Examples this must handle without code changes:

- **Dues per member, in stages.** One invoice per member containing a dues product. The rule tracks the balance remaining against dated milestones: some paid by one date, all paid by a later one. Result: Paid / Partly paid / Not yet paid / Overdue / Not invoiced, plus the balance remaining. Visible to the member, their guardians and their leaders, and copied into a hidden profile field that other features (an eligibility checklist) test.
- **Credits of any kind.** Scholarships, fundraising credit or a refund applied to the invoice lower the balance remaining exactly as a payment does. The rule doesn't care where the money came from.
- **Dues per family.** One invoice per household covering every child. The same rule, with the customer linked to several people.
- **A second fee.** "Travel fee 2027": a new rule filtered on a different product/service.
- **Totals.** "Amount given in 2026", summed from sales receipts and invoices for a donor, visible to admins only.
- **Anything else.** A custom rule with architect-written Ruby, for cases the built-in kinds don't cover.

### 1.1 Non-goals (v1)

- **Writing to the books.** GatherPack never creates or changes anything in QBO (see 4.6). Creating invoices from enrollment or forms is a possible later phase, not this spec.
- **Taking payments.** Families pay through QBO's own invoice pay link, which we only display. The existing Stripe gateway and GatherPack ledgers are unrelated and unchanged.
- **Copying into GatherPack ledgers.** Some organizations track each member's dues in a per-person ledger. Mirroring QBO invoices and payments into ledgers was considered and rejected (1.2).

### 1.2 Why not ledgers

Ledgers are GatherPack's own books: entries people add, edit and pay into. Answering "has this person paid their whole bill" from them would mean copying every invoice in as a charge and every payment as a credit, which is a second set of books beside the accounting system. Specifically:

- **A ledger holds money moved, not money owed.** Paid in full needs the bill, its due date and what was applied to it. Invoices carry all three; ledger entries carry none.
- **Copies drift.** Team managers can edit and delete ledger entries, so a mirrored payment could stop matching the books, and the sync would have to fight those edits.
- **Visibility is too wide.** Every member of a ledger's team sees every ledger of that team (`LedgerPolicy::Scope`), so per-member ledgers on one team expose everyone's payments to everyone. Guardians see a ward's ledger only if added as an owner.
- **The wrong Pay button.** A ledger's Pay goes through the Stripe gateway into GatherPack, not to the organization's own payment route.

The accounting system stays the record. GatherPack keeps a read-only copy (6.1) and shows it per person, including a statement of invoices, payments and credits (8.3), which gives members and guardians the ledger-style view without a second set of books.
- **Line-level payment status.** QBO applies payments to whole invoices, not lines. An invoice holding a matching line counts as a whole (see 6.3).
- **Providers other than QBO.** Table and class names are provider-neutral, so Xero or another system can be added later as a second gateway type. Only QBO is built.
- **QuickBooks Desktop.** It has a different API.
- **Multiple QBO companies at once.** The design allows several connections, and every record carries its gateway. v1 tests and documents one connection.

## 2. What exists today (and what we reuse)

| Piece | Where (upstream unless noted) | Use |
|---|---|---|
| Gateways | `app/models/gateway.rb`, `Gateway.register(klass, svc)`, `gateways.configuration` (jsonb) | `Gateway::QuickbooksGateway`, registered under a new `:accounting` service. Reuses the gateway pages (architects only, `GatewayPolicy < ArchitectPolicy`), the editable `fields`, `finish_setup`, and the `routes` buttons shown on the gateway page (`app/views/gateways/show.html.erb:17`). |
| Gateway webhooks | `POST /gateways/:id/webhook` → `ProcessGatewayWebhookJob` → `Gateway#handle_webhook(payload, headers)`; `self.webhook_headers` | Intuit's change notifications. No new webhook route. |
| Stripe gateway | `app/models/gateway/stripe_gateway.rb` | The pattern to copy: settings in `store_accessor :configuration`, signature check inside `handle_webhook`. |
| Audiences | `AudienceLevels`, `AudienceAccess` (on `feature/person-fields`) | Who may see a rule's results and amounts: `admin`, `self`, `leaders`, `self_and_leaders`, `guardians`, `family`, `team`, `everyone`, plus badge grants. |
| Guardianship | `Person#guardians`, `#wards`, `relationship_types.guardianship` (on `feature/person-fields`) | Guardians see their wards' results when a rule's level includes `guardian`. Email matching suggests a guardian's wards (5.2). |
| Person fields | `PersonField`, `PersonFieldValue` (on `feature/person-fields`) | A rule can write its result into a person field. Trusted callers leave `acting` unset, so no permission check blocks the write. |
| Badges | `Badge`, `BadgeAssignment` | A rule can add and remove a badge (7.1), like the FIRST registration badges. |
| Hooks | `CanBeHooked`, `Hook.catalog`, `Hook#run` (eval) | Record events plus domain events (section 10). `Hook#run`'s eval pattern is also how custom rules run. |
| Reports and widgets | `Report`, `feature/widgets` | Read `AccountingRuleResult` from ERB like any other model. No changes to either. |
| Feature registry | `GatherPack::Features`, `config/initializers/features.rb` | Register `:accounting` in the Finance section, default off. |
| Background jobs | Solid Queue, `config/recurring.yml` | Sync and nightly re-evaluation. |
| HTTP | Ruby `Net::HTTP` | No new gem. `faraday` and `oauth2` are in `Gemfile.lock` only as other gems' dependencies, so we don't rely on them. The old `quickbooks-ruby` gem isn't needed for a read-only JSON client. |

Not present today: Active Record encryption. GatherPack has no `credentials.yml.enc` and no encryption keys configured (4.4).

## 3. QuickBooks Online facts this design depends on

Checked 2026-10-07. Re-verify each one against Intuit's documentation when building, because Intuit changed several of them in 2025–2026.

- **Sign-in.** OAuth 2.0 authorization-code flow with the `com.intuit.quickbooks.accounting` scope. That scope grants read **and** write; there is no read-only scope. The callback returns a `realmId` (the QBO company id). Access tokens last about an hour.
- **Refresh tokens rotate.** Each refresh may return a new refresh token, and the latest one must be saved. Intuit announced a five-year maximum lifetime for refresh tokens, and the token response says when the token expires. A "Reconnect URL" is required in the app's settings in the developer portal.
- **Query API.** `GET /v3/company/{realmId}/query?query=select * from Invoice STARTPOSITION 1 MAXRESULTS 1000`, at most 1000 rows per page. Single records come from `GET /v3/company/{realmId}/{entity}/{id}`. `include=invoiceLink` adds the invoice's online pay link when online payments are on for that invoice.
- **Change Data Capture (CDC).** `GET /v3/company/{realmId}/cdc?entities=Invoice,Payment,...&changedSince=<time>` returns everything changed since a time up to 30 days ago, including deleted records (marked `status: "Deleted"`).
- **Webhooks.** Intuit moved QBO webhooks to the CloudEvents format (migration deadline 2026-05-15). Each delivery is a JSON array of events with `type` (e.g. `qbo.account.created.v1`), `intuitentityid` (the record id), `intuitaccountid` (the realm id) and `time`. Notifications carry ids only, so we fetch the record. Deliveries are signed with an `intuit-signature` header: base64 HMAC-SHA256 of the raw body, keyed with the app's verifier token. Confirm the invoice and payment event names with the portal's "send test event" before relying on them.
- **Limits.** 500 requests a minute and 10 at once per company. Under Intuit's App Partner Program, every app starts on the free Builder tier, which meters "CorePlus" calls (mostly reads: queries, reads, reports) at 500,000 a month per workspace and blocks calls past that until the next month. A team-sized organization uses a few hundred calls a day at most (9.4).
- **Production keys.** Development keys work only against a sandbox company. Production keys require Intuit's app questionnaire plus public URLs for a privacy policy and an end-user license agreement, as well as launch, disconnect and reconnect URLs.

## 4. Connection

### 4.1 `Gateway::QuickbooksGateway`

```ruby
class Gateway::QuickbooksGateway < Gateway
  Gateway.register(self, :accounting)
  include Accounting::Provider            # the interface in 4.5

  store_accessor :configuration, :client_id, :client_secret, :environment, :webhook_verifier_token
  store_accessor :configuration, :synced_entities, :customer_rollup, :match_strategies, :match_field_path
  store_accessor :configuration, :realm_id, :company_name, :connection_status, :last_change_check_at,
                 :last_full_sync_at, :last_error

  def fields
    [ :client_id, :client_secret, :environment, :webhook_verifier_token, :synced_entities,
      :customer_rollup, :match_strategies, :match_field_path ]
  end

  def self.webhook_headers
    [ "HTTP_INTUIT_SIGNATURE" ]
  end
end
```

| Setting | Values | Default | Notes |
|---|---|---|---|
| `client_id`, `client_secret` | from the Intuit app | | Like Stripe's `secret_key`, stored in `configuration`. |
| `environment` | `sandbox`, `production` | `sandbox` | Picks the API host and the deep-link host. |
| `webhook_verifier_token` | from the Intuit app | | Signature check (4.3). With it blank, notifications are ignored and only the regular catch-up runs. |
| `synced_entities` | any of `Customer`, `Invoice`, `Payment`, `CreditMemo`, `SalesReceipt`, `RefundReceipt`, `Item`, `Class`, `Department` | `Customer Invoice Payment CreditMemo Item` | Which record types to copy. Rules can only use types that are copied (6.5). |
| `customer_rollup` | `none`, `parent` | `none` | `parent`: a sub-customer's records also count for people linked to its parent customer (5.1). |
| `match_strategies` | ordered list of `reference`, `name`, `email` | `name email` | How to suggest links (5.2). |
| `match_field_path` | JSON path in a Customer record, e.g. `Notes` | blank | For the `reference` strategy. |
| `realm_id`, `company_name`, `connection_status`, `last_*` | set by the system | | Shown on the gateway page, not editable. `connection_status`: `not_connected`, `connected`, `needs_reconnect`, `disconnected`. |

`routes` returns the gateway page's buttons: **Connect to QuickBooks** (or **Reconnect**), **Sync now**, **Copy everything again**, **Customers**, **Records**, **Disconnect**.

`finish_setup` does nothing. Connecting needs a person at Intuit's sign-in page, which a background job can't do.

### 4.2 Sign-in flow

Routes, drawn from a new `config/routes/accounting.rb` (4.7):

| Route | Action |
|---|---|
| `GET /accounting/connections/:gateway_id/connect` | Architect only. Stores a random `state` (with the gateway id) in the session and redirects to Intuit's authorize URL. |
| `GET /accounting/quickbooks/callback` | The single redirect URI registered with Intuit. Checks `state` against the session, exchanges the code for tokens, saves the tokens and `realm_id`, fetches CompanyInfo for `company_name`, sets `connected`, and queues a full sync (9.1). Then it redirects to the gateway page. |
| `GET /accounting/connections/:gateway_id/disconnect` | Architect only. Revokes the token at Intuit, deletes the saved tokens and sets `disconnected`. Local records stay until the gateway is deleted. This is also the "Disconnect URL" Intuit asks for. |

The person who clicks Connect must be a GatherPack architect, and they must sign in to Intuit as a QBO user who can authorize apps for that company (normally a QBO admin). If those are different people, the architect starts the flow on the QBO admin's computer, or the QBO admin is made an architect for the day. Open question 13.4.

If a different QBO company comes back on reconnect (`realmId` changed), the callback refuses it and says so. Pointing an existing connection at different books would mix two companies' records. Connect the other company as a new gateway instead.

### 4.3 Notifications

`handle_webhook(payload, headers)` runs inside `ProcessGatewayWebhookJob`:

1. Recompute base64 HMAC-SHA256 of the raw `payload` with `webhook_verifier_token` and compare it to `headers["HTTP_INTUIT_SIGNATURE"]` with `ActiveSupport::SecurityUtils.secure_compare`. On mismatch, raise (the job fails visibly, as Stripe's does).
2. Parse the CloudEvents array. Skip events whose `intuitaccountid` isn't our `realm_id`, or whose entity type isn't in `synced_entities`.
3. For each remaining event, queue `Accounting::FetchRecordJob(gateway, entity_type, external_id)`. Deleted events mark the local record deleted instead (6.1).

The controller already answers `204` before any of this runs, so Intuit's response-time limit is met.

**Hosting requirement.** Intuit must reach `/gateways/:id/webhook` without signing in. Where GatherPack sits behind Cloudflare Access, add a bypass for that one path, or skip notifications (leave the verifier token blank) and rely on the regular catch-up.

### 4.4 Token storage

Tokens are the keys to the company's books, so they don't go in `configuration`. New table `accounting_credentials`, prefix `acred`:

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, unique | |
| `access_token` | text | `encrypts` |
| `access_token_expires_at` | datetime | |
| `refresh_token` | text | `encrypts` |
| `refresh_token_expires_at` | datetime | From the token response (3). Drives the "reconnect by" warning. |
| timestamps | | |

No `CanBeHooked` and no `has_paper_trail`. The audit log would otherwise store the token history in plain text.

Encryption keys come from environment variables (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `..._DETERMINISTIC_KEY`, `..._KEY_DERIVATION_SALT`), set in a new initializer `config/initializers/active_record_encryption.rb` only when they're present. Without them, the gateway page says "Set the encryption keys before connecting" and Connect is disabled. `bin/rails db:encryption:init` generates the values. Add them to the deployment's `.env` for Ditto and production.

**Refreshing.** `Accounting::Quickbooks::Client#access_token` refreshes when fewer than five minutes are left. It locks the credentials row (`with_lock`) first and re-reads it, because two jobs refreshing at once would rotate the refresh token twice and lose one. A refused refresh sets `needs_reconnect`, fires `accounting - sync failed` (10), and stops syncing until someone reconnects.

When `refresh_token_expires_at` is under 30 days away, the gateway page and the Accounting rules page show "Reconnect QuickBooks by <date>" to admins.

### 4.5 Provider interface

Everything above the connection layer talks to this interface, never to QBO directly:

```ruby
module Accounting::Provider
  # Yields attribute hashes for every record of the type, a page at a time.
  def each_record(entity_type) = raise NotImplementedError
  # Yields [entity_type, attributes, deleted?] for records changed since time.
  def each_change(entity_types, since) = raise NotImplementedError
  def fetch_record(entity_type, external_id) = raise NotImplementedError
  # Pulls the indexed columns (6.1) out of a raw record.
  def normalize(entity_type, data) = raise NotImplementedError
  # Turns a record into the shape rules use (6.3): totals, balance, due date, line refs.
  def financial_view(record) = raise NotImplementedError
  def customer_name(data) = raise NotImplementedError
  def record_url(record) = nil   # deep link into the provider's own UI
  def entity_types = raise NotImplementedError
  def change_window = nil        # how far back each_change can reach, if limited
end
```

The QBO version lives in `app/models/accounting/quickbooks/` (`Client`, `Normalizer`, `FinancialView`). A future Xero gateway implements the same module.

### 4.6 Read-only, enforced

The OAuth scope lets us write, so read-only is our promise, enforced in code:

- `Accounting::Quickbooks::Client` exposes only `get` and `query`. Its one HTTP method checks that every request is a `GET` to the API host, or a `POST` to Intuit's token or revoke endpoints. Anything else raises before a request is sent.
- A test asserts this (11).
- The gateway page and the Connect button say so: "GatherPack only reads from QuickBooks. It never changes your books."

### 4.7 Routes

`config/routes.rb` gets one line, `draw :accounting`, which loads `config/routes/accounting.rb` (Rails' `draw`, available in Rails 8.1.4). Everything else is in the new file:

```ruby
namespace :accounting do
  get "quickbooks/callback", to: "quickbooks_connections#callback"
  resources :connections, only: [] do
    get :connect, :disconnect, on: :member, controller: "quickbooks_connections"
    post :sync, :full_sync, on: :member, controller: "syncs"
    resources :customers, only: %i[ index show ]
    resources :records, only: %i[ index show ]
  end
  resources :customer_links, only: %i[ create destroy ] do
    post :confirm_all, on: :collection
  end
  resources :rules do
    post :evaluate, on: :member
    get :export, on: :member
  end
end
```

plus, outside the namespace, `get "people/:id/accounting_statement", to: "accounting/statements#show", as: :person_accounting_statement` for the statement (8.3).

Routes are always drawn. Controllers refuse with "Accounting is turned off" when the feature is off, as Forms and Widgets do.

## 5. Customer links

### 5.1 `accounting_customer_links`, prefix `acl`

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | |
| `customer_external_id` | string, required | The QBO Customer id. |
| `person_id` | uuid, required | |
| `source` | string | `confirmed` (an admin confirmed a suggestion), `manual` (an admin picked the person), `reference` (an exact reference-field match, linked automatically; 5.2) |
| `created_by_id` | uuid, optional | Person who confirmed or created it. |
| timestamps | | |

Unique on `(gateway_id, customer_external_id, person_id)`. Model: `include CanBeHooked`, `has_paper_trail versions: { class_name: "AuditLog" }`.

Links are many-to-many:

- **One customer, several people.** A family billed as one customer, linked to each child.
- **One person, several customers.** A student whose customer was re-created, or who appears both as a customer and as a sub-customer.

A person's records for a rule are all records whose customer is linked to them. With `customer_rollup: parent`, sub-customers of a linked customer count too. That's for organizations that bill a family under a parent customer with a sub-customer per child, but link only the family.

### 5.2 Suggestions

Each strategy in `match_strategies` produces suggestions for unlinked customers, with a reason shown to the admin:

| Strategy | Matches | Confirmation |
|---|---|---|
| `reference` | The value at `match_field_path` on the Customer (e.g. its Notes) equals a person's GatherPack id (`per_...`) or their account email. An organization can type the GatherPack id into QBO once, and links follow from then on. | Exact and unique: linked automatically (`source: reference`). Otherwise suggested. |
| `name` | QBO `DisplayName`, or `GivenName` + `FamilyName`, against the person's name, ignoring case, punctuation and accents. Also tries "Last, First". | Always confirmed by an admin. |
| `email` | QBO `PrimaryEmailAddr` against people's account emails. When the matching person has wards (`Person#wards`), the wards are suggested too, labeled "ward of <guardian> (email match)". Where a parent receives each child's invoice, the email usually belongs to the parent, not the person the invoice is for. | Always confirmed by an admin. |

Suggestions are computed when the page loads, not stored. A suggestion an admin dismisses is remembered in `accounting_customer_dismissals` (`gateway_id`, `customer_external_id`, `person_id`) so it doesn't come back.

### 5.3 Customers page

Gateway page → **Customers** (`/accounting/connections/:id/customers`), admins only. Directions at the top: "Link each QuickBooks customer to the people it's for. Rules only see customers that are linked."

- **Needs a link:** each unlinked active customer with its suggestions (person, reason) and **Link** / **Not this person** buttons, plus a person picker. **Link all exact name matches** confirms every suggestion where the name match is exact and the only one.
- **Linked:** each customer with its people, and **Unlink**.
- Inactive QBO customers are hidden behind a "Show inactive" toggle.
- Each customer opens its page: the raw record, its linked people, and its invoices and payments with links into QBO (`record_url`).

The person's profile shows their linked customers to admins (8.3), so a link can also be checked from the person's side.

## 6. Local copy and rules

### 6.1 `accounting_records`, prefix `acr`

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | |
| `entity_type` | string, required | Provider's name: `Invoice`, `Customer`, ... |
| `external_id` | string, required | |
| `sync_token` | string | QBO's version counter. A record whose token hasn't changed isn't saved again. |
| `data` | jsonb, required | The record exactly as the provider returned it. |
| `customer_external_id` | string, indexed | From `CustomerRef` (or the record's own id for a Customer, and `ParentRef` is kept in `data`). Lets rules find a person's records without scanning JSON. |
| `txn_date` | date, indexed | Transaction date, when the type has one. |
| `external_updated_at` | datetime | `MetaData.LastUpdatedTime`. |
| `deleted_at` | datetime | Set when the provider reports a delete. Rules ignore deleted records. Hard-deleted only when the gateway is. |
| `fetched_at` | datetime | |
| timestamps | | |

Unique on `(gateway_id, entity_type, external_id)`. GIN index on `data`. Model: `include CanBeHooked`, **no** `has_paper_trail`. The provider is the history of these records, and keeping copies of every financial record in the audit log would be needless exposure.

`normalize` fills the indexed columns, so a future provider fills the same columns from its own field names.

### 6.2 `accounting_rules`, prefix `arl`

| Column | Type | Notes |
|---|---|---|
| `gateway_id` | uuid, required | |
| `name` | string, required | "2027 Membership Dues" |
| `key` | string, unique | `membership_dues_2027`, generated from the name, fixed once created (like `PersonField#key`). For Reports, Hooks and widgets. |
| `description` | text | Shown to everyone who can see results. |
| `kind` | string, required | `balance`, `amount`, `count`, `custom` (6.3) |
| `filters` | jsonb | 6.4 |
| `settings` | jsonb | Kind-specific: status labels, `grace_days`, `unapplied_credit`, `measure`, `show_pay_links` |
| `code` | text | `custom` only. Architects only. |
| `team_id` | uuid, optional | "Applies to": members of this team and its descendants get a result even with no records (`not_invoiced`, or 0). With no team, only linked people get results. |
| `read_permission` | `AudienceLevels` enum | Who sees a person's result. Default `admin`. |
| `amount_permission` | `AudienceLevels` enum | Who also sees dollar amounts and pay links. Default `admin`. Must be within `read_permission` (as person fields require write ⊆ read). |
| `enabled` | boolean, default true | Off: not evaluated, results hidden, actions paused. |
| `position` | integer | Order on the profile card and the rules list. |
| timestamps | | |

Model: `include CanBeHooked`, `has_paper_trail versions: { class_name: "AuditLog" }`, `belongs_to :team, optional: true`.

Badge grants: `accounting_rule_badge_grants` (`rule_id`, `badge_id`, `amounts` boolean). People with the badge see results for the rule's applicable people, and amounts too when `amounts` is on. This is the same idea as `person_field_badge_grants`, for organizations whose treasurer or mentors aren't team managers.

### 6.3 Kinds

Each kind receives a person's matching records (6.4) and returns a result: `value` (string), `amount_cents` (integer or nil), `details` (hash).

**`balance`** (shown as "Balance remaining"). Uses `Invoice` records. Each invoice goes through `financial_view` (QBO: `TotalAmt`, `Balance`, `DueDate`; voided invoices, which QBO leaves with a zero total, are skipped). Across a person's matching invoices:

- **charged** = the sum of their totals;
- **balance remaining** = the sum of their balances. QBO lowers an invoice's balance whenever anything is applied to it: a payment, a credit memo, a scholarship or fundraising credit, a discount. So every kind of credit counts the same way, with nothing to set up;
- **paid** = charged − balance remaining.

`amount_cents` is the balance remaining. `details` holds charged, paid, each invoice (id, number, date, due date, total, balance, pay link) and each milestone with whether it's met.

**Milestones** say how much must be paid by when. `accounting_rule_milestones`, prefix `arm`, several per rule, edited as rows on the rule form:

| Column | Type | Notes |
|---|---|---|
| `rule_id` | uuid, required | |
| `name` | string, required | "Deposit", "Paid in full" |
| `due_on` | date, required | |
| `balance_at_most_cents` | bigint | One of these two. "Balance at most $250 by Jan 15." |
| `balance_at_most_percent` | integer | "Balance at most 50% of the charge by Jan 15." 0 means paid in full. |
| `position` | integer | Kept in `due_on` order. |

A milestone is met when the balance remaining is at or below its limit. A rule with no milestones uses each invoice's own due date as a single "paid in full" milestone, which is what most organizations need.

| Value | When | Default label |
|---|---|---|
| `not_invoiced` | No matching invoices. | Not invoiced |
| `paid` | Balance remaining is zero. | Paid |
| `overdue` | A milestone whose `due_on` + `grace_days` (default 0) has passed isn't met. | Overdue |
| `partial` | Not overdue, something is paid, and a balance remains. | Partly paid |
| `unpaid` | Not overdue, and nothing is paid yet. | Not yet paid |

Checked in that order (`not_invoiced`, `paid`, `overdue`, then the rest). Labels can be renamed per rule in `settings.labels` (for example "No dues invoice yet"). Where a result is `overdue`, the screens name the missed milestone ("Overdue: Deposit") and, when amounts may be seen, what it takes to catch up ("$150 to meet Deposit"). When it's on schedule, they show the next milestone ("Next: $300 by Mar 1").

**Credit not applied to an invoice.** Money can sit on a customer's account without being applied to an invoice, for example when bulk payouts from an online payment platform are credited by hand. The evaluation adds the linked customers' unapplied payments (`Payment.UnappliedAmt`) and open credit memos (`CreditMemo.Balance`) into `details.unapplied_credit_cents`. The rule's `unapplied_credit` setting says what to do with it:

- `show` (default): the balance remaining follows the invoices only. Unapplied money can't be tied to one charge, so taking it off would be a guess whenever a person has more than one. Instead, the profile card and statement say "A payment of $X is waiting to be applied" to anyone who can see amounts, and the rule page gives admins an "Unapplied credit" mark and filter: a work list of credit to apply in the accounting system.
- `count`: the unapplied amount is taken off this rule's balance remaining before milestones are checked. For organizations where a person only ever has one kind of charge. The rule form says so beside the choice.

`AccountingRuleChange` carries `unapplied_credit_cents` either way, so a hook can skip "overdue" messages to people with credit waiting. Payments and credit memos are in the default `synced_entities`, so neither choice needs more setup.

**`amount`.** `settings.measure` is `invoiced` or `paid`. It sums the matching records: invoices and sales receipts for `invoiced`; payments and sales receipts minus refund receipts for `paid`. (Balance remaining is the `balance` kind.) When `filters.items` is set, only matching lines are summed. `value` is the formatted amount.

**`count`.** The number of matching records. For example, invoices that are overdue, or receipts this year.

**`custom`.** Architect-written Ruby, run like `Hook#run` (`eval(code, binding, ...)`). The code sees `person`, `rule`, `records` (the person's matching `AccountingRecord` scope, already filtered by 6.4) and `customers` (their linked Customer records). It returns a hash `{ value:, amount_cents:, details: }` or a plain string. An exception stores `value: "error"`, shows the message to admins only, and doesn't fire actions.

### 6.4 Filters

`filters` jsonb, every key optional, all combined with AND:

| Key | Meaning |
|---|---|
| `entity_types` | Narrows the record types a kind would use, e.g. only `SalesReceipt` for `amount`. |
| `items` | Product/service ids. A transaction matches if any line references one (QBO: `Line[].SalesItemLineDetail.ItemRef.value`, including lines inside groups). |
| `classes` | Class ids on the transaction or its lines. |
| `departments` | QBO "Locations". |
| `txn_date_from`, `txn_date_to` | Transaction date range, inclusive. |
| `due_date_from`, `due_date_to` | Due date range. |
| `min_total` | Skip transactions below this total, e.g. to ignore $0 placeholders. |

The rule form shows products/services, classes and locations as tick boxes by name, from the local copy. Stored values are ids, so renaming a product in QBO doesn't break a rule. A rule whose filters name a type that isn't in `synced_entities` shows a warning and isn't evaluated.

### 6.5 `accounting_rule_results`, prefix `arr`

| Column | Type | Notes |
|---|---|---|
| `rule_id` | uuid, required | |
| `person_id` | uuid, required | |
| `value` | string | |
| `amount_cents` | bigint | |
| `details` | jsonb | |
| `evaluated_at` | datetime | |
| `changed_at` | datetime | When `value` last changed. |
| `badge_assignment_id` | uuid, optional | The assignment this rule created (7.1). |

Unique on `(rule_id, person_id)`. No `CanBeHooked`: re-evaluation saves `evaluated_at` constantly, and the domain event in section 10 is the useful signal.

This table is what everything reads: the profile card, the rule page, Reports, widgets and Hooks. For example, a report column can use `AccountingRuleResult.joins(:rule).find_by(rules: { key: "membership_dues_2027" }, person:)&.value`. A helper `Person#accounting_result(key)` wraps that.

### 6.6 Evaluation

`Accounting::EvaluateRuleJob(rule, person_ids = nil)` recomputes results and saves only changes. It runs:

- after each sync, for the people linked to customers whose records changed;
- when links are created or removed, for those people;
- when a rule is saved, or someone presses **Evaluate now**, for everyone the rule applies to;
- nightly, for everyone. Milestone and due dates pass without any record changing, so "overdue" depends on the nightly run.

Who a rule evaluates: people linked to any customer, plus members of `team_id` and its descendants when set. A person who no longer qualifies (unlinked, left the team) has their result deleted, and the rule's actions undo (7.1).

## 7. Actions

`accounting_rule_actions`, prefix `ara`: what happens when a result changes. Several per rule.

| Column | Type | Notes |
|---|---|---|
| `rule_id` | uuid, required | |
| `action` | string | `badge`, `person_field` |
| `condition` | jsonb | For status kinds `{ "values": ["paid"] }`. For number kinds `{ "op": ">=", "amount_cents": 50000 }` or `{ "op": ">=", "count": 1 }`. Blank means always. |
| `badge_id` | uuid | For `badge`. |
| `person_field_id` | uuid | For `person_field`. |
| `write` | string | For `person_field`: `label`, `value`, or `amount`. |

### 7.1 Badge

The person has the badge while the condition holds. The rule creates the assignment and records it in `accounting_rule_results.badge_assignment_id`, and removes only that assignment when the condition stops holding. An assignment someone made by hand is never removed, and a person who already has the badge by hand is left alone. A badge tied to a team is only given to that team's members; a non-member is skipped and noted in `details`, as `BadgeAssignment`'s validation would refuse it anyway.

This is how results reach everything that already understands badges: the Eligibility Report, badge filters on people lists, and widgets.

### 7.2 Person field

Writes the label, value or amount into the field, or clears it when the condition doesn't hold. The write leaves `acting` unset (a trusted caller), so it fires `person_fields - value changed` like any other write. The rule form warns when the field's `write_permission` isn't `admin`, because people could then overwrite a value the rule will put back at the next evaluation.

Using a person field lets an organization put a result in a profile section next to related details, under person-field access rules. Most rules won't need it: the rule's own profile card (8.3) already shows results under the rule's permissions.

## 8. Screens

### 8.1 Navigation

Feature registration:

```ruby
GatherPack::Features.register_built_in(
  GatherPack::Feature.new(
    key: :accounting,
    label: "Accounting",
    description: "Read invoices and payments from your accounting system",
    default_enabled: false,
    nav_section: "Finance",
    nav_position: 40,
    nav_items: [ GatherPack::Feature::NavItem.new(label: "Account Status", path: :accounting_rules_path, icon: "file-invoice-dollar") ]
  )
)
```

The side-nav link appears for anyone who can see at least one rule's results for someone (admins, leaders, people with a badge grant). Everyone else reaches their own results from their profile.

Connections stay under Setup → Gateways with the other gateways.

### 8.2 Account Status (`/accounting/rules`)

- **List:** each enabled rule the viewer can see results for, with counts per value among the people they can see ("Paid 41 · Partly paid 3 · Overdue 6 · Not invoiced 2"). Admins also see disabled rules, the connection's status and last sync time, and the reconnect warning.
- **Rule page:** a table of people the viewer can see: name, team, value (colored by value), amount (if permitted), "changed on" date, and links into QBO for admins. It has a filter by value and team, a CSV export of the same table, and a print layout using the shared report print CSS. Admins get **Edit** and **Evaluate now**.
- **Rule form** (admins; `code` and `kind: custom` architects only, as Widgets does for JavaScript):
  - Name, Description
  - What it answers: kind, then the kind's options (milestones, grace days, unapplied credit, labels, measure)
  - Which records: the filters in 6.4
  - Who it applies to: everyone linked, or a team
  - Who can see it: result level, amount level, badge grants
  - When the result changes: actions
  - Enabled
  - Directions at the top: "A rule answers one question from your accounting records for each person, like 'Are their dues paid?'. Pick which records count, who it's for, and who can see the answer."
  - A **Preview** button evaluates the unsaved rule for five linked people and shows their results, without saving anything or firing actions.

### 8.3 Profile card

One `render "accounting/person_card", person: @person` line in `app/views/people/show.html.erb`. The partial renders nothing when the feature is off or the viewer can see no rule for this person. Otherwise, a card titled **Account** lists each rule the viewer can see:

- name, value, "as of" time
- amount, invoice list and **Pay online** links when the viewer meets `amount_permission` and `settings.show_pay_links` is on
- the "waiting to be applied" line from 6.3 when there is unapplied credit
- a **Statement** link, when the viewer meets `amount_permission` for at least one rule
- for admins: linked customers, with **Manage links**

Guardians see this on their ward's profile, which they can already open.

**Statement** (`/people/:id/accounting_statement`): one table, newest first, of the person's records that the viewer may see amounts for: the invoices matched by those rules, the payments and credit memos applied to them (from each invoice's `LinkedTxn`), and the linked customers' unapplied payments and credits. Columns: date, what it is ("Invoice 1042 · Membership Dues", "Payment", "Credit"), charge, payment, and running balance, with the current balance at the top. Admins see every record of the linked customers and a link into QBO on each row. Read-only, with the shared print layout. This is the ledger-style view organizations ask for (1.2), drawn from the books rather than kept beside them.

### 8.4 Records (admins)

Gateway page → **Records**: the local copy, filterable by type, customer and date, each showing its raw JSON and a link into QBO. This is for checking what GatherPack sees and writing custom rules. No editing.

## 9. Sync

### 9.1 Jobs

All sync jobs for one gateway run one at a time (`limits_concurrency to: 1, key: ->(gateway, *) { gateway.id }`). This keeps us under Intuit's concurrency limit, and keeps two jobs from refreshing the token at once.

| Job | What it does |
|---|---|
| `Accounting::FullSyncJob(gateway)` | For each type in `synced_entities`: page through `each_record`, upsert, and mark records missing from the result as deleted. Customers include inactive ones (`where Active IN (true, false)`). Sets `last_full_sync_at` and `last_change_check_at`, then queues evaluation. |
| `Accounting::ChangesJob(gateway)` | `each_change(synced_entities, last_change_check_at)`: upsert, mark deleted, advance `last_change_check_at` to the request time, queue evaluation for affected people. If `last_change_check_at` is older than `change_window` (30 days), runs a full sync instead. |
| `Accounting::FetchRecordJob(gateway, type, id)` | One record, from a notification. |
| `Accounting::EvaluateRuleJob(rule, ids)` | 6.6. |

### 9.2 Schedule

Added to `config/recurring.yml`:

```yaml
accounting_changes:
  class: Accounting::ScheduleChangesJob   # queues ChangesJob for each connected gateway
  queue: default
  schedule: every 15 minutes
accounting_nightly:
  class: Accounting::NightlyJob          # weekly full sync on Sundays, nightly evaluation of every enabled rule
  queue: default
  schedule: at 3am every day
```

Both do nothing when the feature is off or no gateway is connected.

### 9.3 Failures

- **401** after a refresh: `needs_reconnect`.
- **429 or 5xx:** retry with backoff (`retry_on`, up to 5 attempts).
- **Anything else:** stores `last_error`, fires `accounting - sync failed`, and leaves the previous local data in place. Results never go blank because a sync failed.

The rules page shows admins "Last synced ... ago" in red when it's more than a day old.

### 9.4 Call budget

At team scale (about 500 customers, 1,000 transactions a year):

- **Full sync:** about 1 call per 1,000 records per type, so about 10 calls.
- **Changes job:** 96 calls a day.
- **Notifications:** one fetch per changed record.

A busy month is under 5,000 calls, about 1% of the Builder tier's 500,000. The gateway page shows the month's call count (a counter in `configuration`) so an organization can see it.

## 10. Hooks

Record events (`include CanBeHooked`, add to `Hook.catalog`):

| Table | Why |
|---|---|
| `accounting_records` | React to any accounting change directly, e.g. post to a channel when a payment over a set amount arrives. Fires only when `sync_token` changed, not on every sync. |
| `accounting_customer_links` | Audit or notify when someone links a person to a customer. |
| `accounting_rules` | Someone changed what a rule answers or who can see it. |

Domain events, added to `Hook.catalog` on their own line, like `token - activate`:

- **`accounting_rules - result changed`.** `model` is an `AccountingRuleChange` (plain Ruby, like `PersonFieldChange`) with `rule`, `person`, `old_value`, `new_value`, `old_amount_cents`, `new_amount_cents`, `unapplied_credit_cents`. Fired after the result is saved and actions have run. This is the main integration point: "email the guardians when dues become overdue", "tell the treasurer when a family pays".
- **`accounting - sync failed`.** `model` is the gateway; `last_error` and `connection_status` say why. Covers expired sign-ins.
- **`accounting - customer unlinked`.** `model` is the new `AccountingRecord` (Customer). Fired when a new customer arrives and no automatic link was made, so someone can be told to link it.

Not hookable:

- `accounting_rule_results`: covered by the result-changed event, which avoids an update on every nightly evaluation.
- `accounting_credentials`: secrets.
- `accounting_customer_dismissals`, `accounting_rule_badge_grants`, `accounting_rule_actions`: settings rows. Changes show in the audit log through their rule.

Data note: Hook and custom-rule code runs with full access to every record, including amounts the viewer of a page may not be allowed to see. That's the existing contract for architect code, and it's restated in the rule form's directions for the code field.

## 11. Tests (Minitest)

No WebMock in the Gemfile, and none is added. `Accounting::Quickbooks::Client` takes a transport object. Tests pass a fake transport that returns fixtures recorded from the sandbox (`test/fixtures/files/quickbooks/*.json`) and records the requests it was asked to make.

- **Client:**
  - refuses any non-GET to the API host, and POSTs anywhere but the token and revoke endpoints;
  - refreshes when the token is near expiry;
  - saves the rotated refresh token;
  - two concurrent refreshes make one call;
  - a refused refresh sets `needs_reconnect`.
- **Webhook:**
  - a valid signature queues fetches;
  - a bad signature raises;
  - other realms and unsynced types are ignored;
  - a deleted event marks the record deleted.
- **Sync:**
  - full sync pages past 1,000 rows and marks missing records deleted;
  - the changes job advances its time and falls back to a full sync past 30 days;
  - an unchanged `sync_token` doesn't save or fire hooks.
- **Links:**
  - each strategy's suggestions, including email → wards;
  - an exact reference match links automatically;
  - dismissals stick;
  - parent rollup includes sub-customers.
- **Kinds:**
  - each `balance` value and the order they're checked in;
  - applied credit memos and other credits lower the balance remaining like payments;
  - milestones by amount and by percent, met and missed, and the next-milestone and catch-up amounts;
  - a rule with no milestones uses each invoice's due date;
  - voided invoices skipped;
  - grace days;
  - unapplied payments and open credit memos fill `unapplied_credit_cents`; `show` leaves the balance alone, `count` takes it off;
  - `amount` sums only matching lines when items are filtered;
  - a `custom` rule's return shapes and its error handling.
- **Filters:** items inside group lines; class on line vs transaction; date bounds inclusive.
- **Actions:**
  - the badge is added and removed;
  - a hand-made assignment is never removed;
  - a team badge skips non-members;
  - a person field is written and cleared.
- **Permissions:**
  - results and amounts at each audience level for the subject, a guardian, a leader, a teammate and a stranger;
  - badge grants;
  - `amount_permission` ⊆ `read_permission`;
  - non-architects can't set `code` or `kind: custom`;
  - the profile card renders nothing for someone who may see no rule;
  - the statement lists only records under rules whose amounts the viewer may see, and everything for admins.
- **Hooks:** each catalog entry fires with the right model; no result-changed event when the value is unchanged.
- **Feature off:** routes refuse, the card and nav don't render, the recurring jobs do nothing.

Manual, against the Intuit sandbox company before production keys:

- connect, disconnect, reconnect;
- the portal's "send test event";
- a payment made in the sandbox turning a result from `open` to `paid` within a minute with notifications, or within 15 minutes without.

## 12. Fork strategy

**Branch.** `feature/accounting` from `feature/person-fields`, declared in `fork/features.txt` after person-fields, as `feature/forms` is. It depends on person-fields for `AudienceLevels`, `AudienceAccess`, guardianship and person fields.

**Naming.** Upstream-style names (`Accounting::`, `accounting_*`), no `Hbr` namespace, the same decision as forms: generic code, nothing HBR-specific.

**Flag.** `:accounting` in `GatherPack::Features`, default off.

**New files.** Models, jobs, controllers, policies, views, the route file, the encryption initializer, breadcrumbs, tests and fixtures.

**Upstream files touched** (for `FORK.md`):

| File | Change |
|---|---|
| `config/routes.rb` | `draw :accounting` |
| `config/initializers/features.rb` | The registration in 8.1. |
| `app/models/hook.rb` | `"accounting_records", "accounting_customer_links", "accounting_rules"` and the three domain events, on their own line. Person-fields, forms and widgets edit the same method, so expect a rebuild conflict until rebased. |
| `config/recurring.yml` | Two entries, appended. |
| `app/views/people/show.html.erb` | One `render` line. Person-fields also edits this file, which is why the branch sits on it. |
| `db/schema.rb` | New tables and the version line (handled by `bin/fork-merge-schema`). |

**Migrations.** One per table, all reversible:

- `accounting_credentials`
- `accounting_records`
- `accounting_customer_links`
- `accounting_customer_dismissals`
- `accounting_rules`
- `accounting_rule_milestones`
- `accounting_rule_badge_grants`
- `accounting_rule_actions`
- `accounting_rule_results`

### 12.1 Rollout

1. Connection, credentials, client, full sync, changes job, Records page. Built and tested against the Intuit sandbox.
2. Customer links and the Customers page.
3. Rules, kinds, results, the Account Status pages and the profile card.
4. Actions and Hooks.
5. On Ditto: production keys, connect the company, link customers, set up the organization's rules, compare against the treasurer's own aging report.
6. Release in an `-hbr.N` tag with the feature off. Turn it on in production after the Ditto comparison matches.

### 12.2 Worked example (configuration, not code)

A club bills each member their own invoice, siblings included, and wants a deposit by one date and everything by another. Members pay through a platform that pays out in bulk, and the treasurer applies the money to each member's account by hand.

| Setting | Value |
|---|---|
| `match_strategies` | `name email`. Each member is their own customer; parents receive their children's invoices, so email matches find the parent and suggest their wards. |
| `customer_rollup` | `none`. |
| Rule | kind `balance`, items = the dues product, transaction dates within the season, applies to the members' team, `unapplied_credit: show`. |
| Milestones | "Deposit": balance at most 50% by the first date. "Paid in full": balance at most 0 by the second. |
| Visibility | `read_permission: family`, `amount_permission: family`, `show_pay_links` on. |
| Actions | `person_field`, always, `write: label`, into a "Dues" select field whose choices match the rule's labels: admin-written, read at `family`, hidden from profiles. The rule's own card already shows the status to the people allowed to see it, so the field exists only for other features to test. A badge would work too, but shows on the profile to everyone who can open it. |
| Using it | An eligibility checklist item tests the field: "Dues is any of Paid" for full eligibility, or "is none of Overdue" for "on schedule". Checklist results say pass or not, never the value. |

### 12.3 Intuit setup checklist (when picked up)

1. Create the Intuit developer account with a team-owned email address, not a personal one, so the app outlives any one volunteer.
2. Create the app, with scope Accounting. Note the sandbox company.
3. Redirect URIs:
   - `http://localhost:3000/accounting/quickbooks/callback` (development)
   - Ditto's and production's `https://.../accounting/quickbooks/callback`
4. Webhooks: endpoint `https://<host>/gateways/<gateway id>/webhook`, CloudEvents format, entities Customer, Invoice, Payment, CreditMemo, Item. Copy the verifier token into the gateway. Add the Cloudflare Access bypass for that path.
5. Production keys: complete the questionnaire. Publish privacy policy and EULA pages, and give the launch (the gateway page), disconnect (4.2) and reconnect (connect, 4.2) URLs.
6. Generate encryption keys (`bin/rails db:encryption:init`) for Ditto and production and add them to each `.env`. Restarting production to pick them up is Corey's step.

## 13. Open questions

1. **Name in the UI.** "Account Status" for the nav link and "rules" for the questions. ("Checks" was avoided because it reads as paper checks in a finance screen.)
2. **Who manages links and rules.** v1 says admins. An organization might want a treasurer who isn't an admin. That could become a badge grant with a "manage" flag later.
3. **Partial payments.** Decided: configuration. Milestones say how much must be paid by when (6.3), and whatever tests the result decides what passes (an action condition, or a checklist item accepting several labels).
4. **Who clicks Connect.** Architect plus a QBO admin at the same browser (4.2), or a one-time handoff link the QBO admin can open without being a GatherPack architect.
5. **Upstream.** Not planned. Only Corey raises it.
