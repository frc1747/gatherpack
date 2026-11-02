# MCP server spec

Builds the feature described in [`fork/pitches/06-mcp-server.md`](../pitches/06-mcp-server.md). The pitch says what and why; this spec says exactly what to build: branches, sign-in, the transport, the tool registry, every tool's contract and permission rule, settings, the call log, hooks and tests.

## 1. Principles

1. **A tool shows nothing a page wouldn't.** Every read tool names the existing page that shows the same data and applies that page's checks: the controller's `policy_scope` and `authorize` calls, plus any filtering its view does (person fields, guardian-only parts). Where a tool has no matching page, it uses the strictest rule of the nearest page and says so in its class comment.
2. **Never trust a default-true policy.** `ApplicationPolicy` allows every action that a policy doesn't define, and some scopes return everything (`CheckinPolicy::Scope`, `BadgeAssignmentPolicy::Scope` are `scope.all`). A tool may rely on a policy method only if that policy defines it. Otherwise it gates on the parent record the page is reached through (the person, the event, the badge). Each tool's test proves the low-privilege case.
3. **Tools do their own checks.** The MCP controller authenticates and nothing else. Every tool runs `policy_scope`/`authorize` itself, as the token's user, through a small `Mcp::Context` (below).
4. **One change per write call, by ID.** Writes take neat IDs (`per_…`, `bdg_…`), never names, change one record, and return the record they changed. No bulk writes and no lookups by name inside a write.
5. **Generic, no organization words.** Tool names and descriptions use GatherPack's own terms (person, team, badge, event, check-in, time clock, ledger, form, sign-up sheet, commitment).
6. **Add, don't edit.** New files, `config/initializers/mcp*.rb`, and three upstream edits (§9).

## 2. Branches

| Branch | Base | Contents |
|---|---|---|
| `feature/mcp` | `upstream/main` | Flag, settings, sign-in discovery, scopes, transport, registry, call log, core tools (people, teams, badges, events, check-ins, time clock, ledgers) and core writes |
| `feature/mcp-person-fields` | `feature/person-fields` + `feature/mcp` | Person field tools |
| `feature/mcp-forms` | `feature/forms` + `feature/mcp` | Form tools |
| `feature/mcp-signups` | `feature/signups` + `feature/mcp` | Sign-up sheet tools and sign-up writes |
| `feature/mcp-commitments` | `feature/commitments` + `feature/mcp` | Commitment tools |

Each connector branch is created from its feature branch with `feature/mcp` merged in, like `feature/signup-credit`. It adds only new files and one initializer that registers its tools when both features are present. `feature/mcp` alone is upstream-adoptable; each connector goes with its feature.

Manifest position (needs the fork owner's approval, rule 8): after `feature/pagination-labels`, in the order above.

## 3. Feature flag and settings

`config/initializers/mcp.rb`, inside `to_prepare`:

- `GatherPack::Features.register(GatherPack::Feature.new(key: :mcp, label: "MCP server", description: "Let members' AI clients read and change data as the member, within their permissions", default_enabled: false, toggleable: true, setup_items: [...]))`. No nav items for members. A setup item links admins to **MCP calls** (§8).
- `Settings.register(:mcp_allowed_badge, :string, "MCP: allowed badge", "", <group>, "Only holders of this badge can connect. Blank: every member.")`. Stores a badge neat ID; the settings form should offer a badge select if the settings page supports one, otherwise a neat ID text field.
- `Settings.register(:mcp_write_enabled, :boolean, "MCP: allow changes", "false", <group>, "Off: MCP clients can only read.")`.

Confirm `Settings.register`'s argument order and the group name in `lib/settings.rb` before writing these. Settings are cached per process (gp-map); tests use `with_settings`.

**Who may use it** (`Mcp::Access.allowed?(user)`): the feature is on, `oauth_provider` is on, the user has a person, and either `mcp_allowed_badge` is blank or the person holds that badge (admins too: the badge limit applies to everyone, so it can be used for a trial). Writes additionally need `mcp_write_enabled` and the `mcp_write` scope.

## 4. Sign-in

### 4.1 Scopes

`mcp_read` and `mcp_write`. A token with `mcp_write` can call read tools too.

Add them without editing `config/initializers/doorkeeper.rb` if Doorkeeper allows it: in `config/initializers/mcp.rb`, after Doorkeeper is configured, add them to `Doorkeeper.config.optional_scopes` (check `Doorkeeper::OAuth::Scopes#add` and whether the config object is frozen in 5.9). If that doesn't work cleanly, add them to the `optional_scopes` line in `doorkeeper.rb` and list the file in FORK.md. Scope names must show in plain words on the consent page: add i18n keys `doorkeeper.scopes.mcp_read` ("Read your GatherPack data through an AI assistant") and `doorkeeper.scopes.mcp_write` ("Make changes in GatherPack through an AI assistant") in a new `config/locales/mcp.en.yml`.

### 4.2 PKCE

Required for any authorization request that asks for an `mcp_*` scope, `S256` only. Doorkeeper's `force_pkce` is global and would break existing OAuth clients that don't send PKCE, so don't set it. Instead, in the initializer: `Doorkeeper::AuthorizationsController.before_action` that, when the requested scopes include `mcp_read` or `mcp_write` and `code_challenge` is missing or `code_challenge_method` isn't `S256`, renders Doorkeeper's `invalid_request` error. Test both sides: an MCP request without PKCE is refused; a `user_read` request without PKCE still works.

### 4.3 Clients

Pre-registered only, on the existing OAuth Applications page (admin). No dynamic client registration endpoint. Setup notes in §11.

### 4.4 Discovery

MCP clients find the sign-in through two metadata documents (MCP authorization spec, RFC 9728 and RFC 8414). Served by `Mcp::MetadataController` (inherits `ActionController::API` or `ApplicationController` with sign-in checks skipped; no session):

- `GET /.well-known/oauth-protected-resource` and `GET /.well-known/oauth-protected-resource/mcp`: `{ resource: "<base>/mcp", authorization_servers: ["<base>"], scopes_supported: ["mcp_read", "mcp_write"], bearer_methods_supported: ["header"] }`.
- `GET /.well-known/oauth-authorization-server`: `issuer`, `authorization_endpoint` (`oauth_authorization_url`), `token_endpoint`, `revocation_endpoint`, `scopes_supported` (Doorkeeper's full scope list), `response_types_supported: ["code"]`, `grant_types_supported: ["authorization_code", "refresh_token"]`, `code_challenge_methods_supported: ["S256"]`, `token_endpoint_auth_methods_supported: ["client_secret_post", "client_secret_basic", "none"]`. Build URLs from Doorkeeper's route helpers, not hard-coded paths. If the app already serves either document (check routes for `.well-known` and the OIDC work), extend that instead of adding a second.

Both return 404 when the MCP feature is off. `<base>` is the request's base URL.

An unauthenticated or invalid-token request to `/mcp` gets `401` with `WWW-Authenticate: Bearer resource_metadata="<base>/.well-known/oauth-protected-resource"` (and `error="invalid_token"` when a token was sent). A token without an MCP scope gets `403` with `error="insufficient_scope", scope="mcp_read"`. A valid token whose user fails `Mcp::Access.allowed?` gets `403` with a JSON-RPC error body explaining that MCP isn't enabled for their account.

The OAuth `resource` parameter (RFC 8707) is accepted and ignored; tokens are bound by scope, not audience.

## 5. Transport

Gem: `mcp` (the official Ruby SDK, `modelcontextprotocol/ruby-sdk`), added to the `Gemfile`; `Gemfile.lock` regenerated with `bundle lock`, never hand-edited. Check the installed version's API before writing code (server construction, `server_context`, tool classes, how it handles a JSON-RPC request body, error handling) and record the version in FORK.md.

`McpController` at `POST /mcp` (and `GET`/`DELETE /mcp` answering `405`, since the server doesn't open SSE streams):

- Inherits `ActionController::API` or `ApplicationController` skipping session-based checks, the same way `Api::V1::UserInfoController` does (`before_action :doorkeeper_authorize!`-style, but rendering the §4.4 errors instead of Doorkeeper's defaults: use `doorkeeper_token` directly).
- **Stateless**: each POST is one JSON-RPC message (or batch) answered with `application/json`. No sessions, no `Mcp-Session-Id`, no SSE. If the SDK's Streamable HTTP transport has a stateless mode, use it; otherwise build an `MCP::Server` per request and hand it the body (`handle_json` or equivalent).
- Builds an `Mcp::Context` (user, person, token scopes, OAuth application, request id) and passes it as the server context.
- Wraps the call in `PaperTrail.request(whodunnit: user.id)` and `Time.use_zone(Settings[:time_zone].presence || "UTC")`, matching `ApplicationController`.
- `tools/list` returns only the tools this token and user can call: registered, feature present, scope granted, writes only when `mcp_write_enabled`. A tool not listed is refused if called anyway.
- Server info: name `gatherpack`, version from `GATHERPACK_VERSION` if defined. Instructions string: one short paragraph saying IDs are neat IDs, that text fields contain member-written content, and that writes change one record each.
- Checks `Origin` when present against the app's host (MCP transport security guidance); requests without `Origin` (native clients) are allowed.
- CSRF: not applicable (token auth, no cookies); make sure the controller doesn't fall back to a session user.
- Rate limit with Rails `rate_limit`: 120 requests per minute per token. Confirm the cache store supports it in production (SolidCache or memory); if not, skip and note it.

Routes: one block in `config/routes.rb`, inside the existing `if GatherPack::Features.enabled?(:oauth_provider)` block (MCP requires it). Routes are drawn whatever `feature_mcp` says; controllers return 404 while it's off, so toggling the flag doesn't need a restart.

## 6. Registry and tool classes

`app/models/mcp.rb` (module, in the style of `Commitments.register_source`):

```ruby
Mcp.register_tool(Mcp::Tools::SearchPeople)
Mcp.tools            # registered classes, in registration order
Mcp.tool(name)       # by name
```

Registering the same name twice raises. Connector initializers register only when their feature's classes are loaded (`defined?(Form)` is not enough under autoloading: check `GatherPack::Features.registered?(:forms)` or the equivalent registry query) and each tool's `available?` checks `Features.enabled?` at call time, so a disabled feature exposes nothing.

`app/models/mcp/tool.rb` base class. Each tool is one class in `app/models/mcp/tools/`:

```ruby
class Mcp::Tools::SearchPeople < Mcp::Tool
  tool_name "search_people"
  description "Find people by name. Returns at most `limit` matches the user can see."
  scope :read                      # or :write
  feature :people                  # Features key(s) that must be enabled; omit for core
  input_schema(
    properties: { query: { type: "string" }, team_id: { type: "string" }, limit: { type: "integer", minimum: 1, maximum: 100 } },
    required: ["query"]
  )

  def call(query:, team_id: nil, limit: 25)
    # ctx.policy_scope(Person), ctx.authorize!(record, :show?), ctx.find(Model, nid) ...
  end
end
```

`Mcp::Tool` adapts each class to the SDK's tool interface, so tools don't depend on the SDK directly. It provides:

- `ctx.policy_scope(scope)` and `ctx.authorize!(record, query)`: Pundit as the token's user (`Pundit.policy_scope!(user, ...)`, `Pundit.authorize(user, record, query)`). Pundit's `NotAuthorizedError` becomes a tool error "Not allowed", never a stack trace.
- `ctx.find(scope, nid)`: `NeatIds.find`-style lookup restricted to the given scope and the expected model; a wrong prefix or a record outside the scope is "Not found" (don't reveal that it exists).
- Results: JSON. Return `structuredContent` and the same JSON as a single text content block (clients differ in which they read). Declare `output_schema` where the SDK supports it.
- Lists default to 25 and cap at 100, return `{ items: [...], truncated: true|false }`, and order deterministically.
- Times are ISO 8601 in the app time zone. Dates are `YYYY-MM-DD`. Durations are decimal hours rounded to 0.01. Money is `{ cents:, formatted: }`.
- People are always returned in one compact shape, `{ id: "per_…", name: }`, plus whatever the tool adds. Never return emails, phone numbers or addresses unless the matching page shows them to this viewer (§7.1).
- Tool annotations where the SDK supports them: `readOnlyHint: true` on read tools; `destructiveHint` on removals.
- Every call goes through `Mcp::CallLog` (§8), success or failure.

Errors returned as tool results (`isError: true`, a short message): not found, not allowed, invalid argument, feature off, writes disabled. Unexpected exceptions are logged with the request id and returned as "Internal error"; never the exception message.

## 7. Tools

Each row: name, inputs, what it returns, and the permission rule. "Page" names the screen whose checks the tool mirrors; confirm each against its controller and view before writing the tool, and write the rule actually used into the class comment.

### 7.1 Core, read (`feature/mcp`, scope `mcp_read`)

| Tool | Inputs | Returns | Permission (page) |
|---|---|---|---|
| `whoami` | — | Your person, whether admin, teams you belong to and manage, granted scopes, whether writes are enabled | Always |
| `search_people` | `query`, `team_id?`, `badge_id?`, `limit?` | People matching the name (case-insensitive, like upstream's `_i_cont` searches) with their teams | `policy_scope(Person)` (people index). Team filter: team must be in `policy_scope(Team)`. Badge filter: same rule as `get_badge` holders |
| `get_person` | `person_id` | Name, contact details and other base profile fields the profile page shows this viewer, teams (with manager flag), badges, guardians and wards | `authorize person, :show?` (people/show). Copy the view's own conditions for contact details and relationships; a teammate sees what the profile shows a teammate. Badges only if the badges feature is on |
| `list_teams` | `parent_id?` | Teams with parent, member count | `policy_scope(Team)` (teams index) |
| `get_team` | `team_id` | Team, parent, child teams, members with manager flag | `authorize team, :show?` if `TeamPolicy` defines it, otherwise team in `policy_scope(Team)`; members as the team page lists them |
| `list_badges` | — | Badges with type and holder count | `policy_scope(Badge)` (badges index); badges feature on |
| `get_badge` | `badge_id` | Badge and its holders | Holders: only if `BadgeAssignmentPolicy#index?` (badge editors), otherwise only holders in `policy_scope(Person)`. Never `BadgeAssignmentPolicy::Scope` alone (it's `scope.all`) |
| `list_events` | `from`, `to`, `team_id?`, `event_type_id?`, `limit?` | Events with team, type, times, attendee count | `policy_scope(Event)` (events index). Window ≤ 366 days |
| `get_event` | `event_id` | Event and attendees (check-ins with times) | Event in `policy_scope(Event)`; attendees as the event page shows them (check the view for manager-only parts) |
| `list_checkins` | `person_id`, `from`, `to` | A person's check-ins with event | `authorize person, :show?` (profile recent activity). `CheckinPolicy::Scope` is `scope.all`; don't rely on it |
| `time_clock_hours` | `person_id?` or `team_id?` (one required), `from`, `to` | Hours per person in the range, from closed punches; open punches counted to now and flagged | Mirror the time clock summary page (`TimeClockPeriodPolicy#summary?` and `TimeClockPunchPolicy::Scope`); for one person also `authorize person, :show?` |
| `clocked_in_now` | `team_id?` | People with an open punch, since when, and the period | `TimeClockPunchPolicy::Scope` plus person visibility; match whatever upstream page lists open punches |
| `list_ledgers` | — | Ledgers with team and balance | `policy_scope(Ledger)`; finance feature on |
| `ledger_entries` | `ledger_id`, `from?`, `to?`, `tag?`, `limit?` | Entries with date, description, amount, tags, status, split parent | Ledger in `policy_scope(Ledger)`, entries via `policy_scope(LedgerEntry)` |

### 7.2 Core, write (`feature/mcp`, scope `mcp_write`, setting `mcp_write_enabled`)

| Tool | Inputs | Effect | Permission |
|---|---|---|---|
| `assign_badge` | `person_id`, `badge_id` | Creates a `BadgeAssignment`; returns it | Same as `BadgeAssignmentsController#create` (`BadgeAssignmentPolicy#create?`, team-badge membership validation) |
| `remove_badge` | `badge_assignment_id` | Destroys it | `BadgeAssignmentPolicy#destroy?` |
| `add_team_member` | `person_id`, `team_id`, `manager?` | Creates a `Membership` | `MembershipPolicy#create?`; `manager: true` only if the controller allows this viewer to set it |
| `remove_team_member` | `membership_id` | Destroys it | `MembershipPolicy#destroy?` (if undefined it defaults to true: then use what `MembershipsController#destroy` checks, or refuse) |
| `record_checkin` | `person_id`, `event_id` | Creates a `Checkin` with `created_by` set | `CheckinPolicy#create?` as `CheckinsController#create` uses it, plus event and person visibility |
| `create_event` | `team_id`, `event_type_id`, `name`, `starts_at`, `ends_at`, `location?` | Creates an `Event` with `team_id` set (team-less events are invisible to non-admins, gp-map) | `EventPolicy#create?` as `EventsController#create` uses it; team in the viewer's scope |

Each write runs the model's validations and returns validation messages as an "invalid argument" error. Writes run inside `PaperTrail.request(whodunnit:)` (§5) and log the changed record in the call log.

### 7.3 Person fields (`feature/mcp-person-fields`, read)

| Tool | Inputs | Returns | Permission |
|---|---|---|---|
| `get_person_fields` | `person_id` | Field values grouped by field group, with type | `authorize person, :show?`, then `person.readable_fields_for(ctx.person)` (uses `PersonField#readable_by?`, including guardian levels) |

Also registers an extension so `get_person` includes a `fields` key with the same data when person fields is on. Add a small hook in the core tool (`Mcp.person_extensions`, a list of callables `(person, viewer) -> Hash`) rather than editing `get_person` from the connector.

### 7.4 Forms (`feature/mcp-forms`, read)

| Tool | Inputs | Returns | Permission (page) |
|---|---|---|---|
| `list_forms` | `status?` (open/closed/all) | Forms with deadline and counts (assigned, submitted) | Forms index rules (`FormPolicy#index?`/`show?`); only forms the viewer can manage show counts |
| `form_status` | `form_id` | Who is assigned, who has submitted (with time), who hasn't | `FormPolicy#results?` (results page) |
| `form_answers` | `form_id`, `person_id?`, `limit?` | Submitted answers by question, per person | `FormPolicy#results?` and, per response, `FormResponsePolicy#show?`; answers that map to person fields filtered with `readable_by?`, as the results view does |

### 7.5 Sign-ups (`feature/mcp-signups`)

| Tool | Scope | Inputs | Returns / effect | Permission |
|---|---|---|---|---|
| `list_signup_sheets` | read | `from?`, `to?` | Sheets with event, open and filled counts | `policy_scope(SignupSheet)` + `show?` |
| `get_signup_sheet` | read | `sheet_id` | Parts, positions, slots, who holds each (and on whose behalf), open places | `SignupSheetPolicy#show?`; names as the sheet page shows them (`roster?` for full roster) |
| `person_signups` | read | `person_id` | A person's upcoming sign-ups | Person `show?` plus sheet visibility per sign-up |
| `place_signup` | write | `slot_id`, `person_id` | Places the person in the slot | `SignupPolicy#place?` (or `create?` for self/relative), through the same service the controller uses, so rules, capacity and hooks run |
| `remove_signup` | write | `signup_id` | Cancels it | `SignupPolicy#destroy?`, through the controller's service |

### 7.6 Commitments (`feature/mcp-commitments`, read)

| Tool | Inputs | Returns | Permission |
|---|---|---|---|
| `list_commitments` | — | Current commitments the viewer can see | `PersonCommitmentsPolicy#visible_commitments` |
| `commitment_progress` | `commitment_id`, `person_id?` | Owed, planned, confirmed and balance per person or group; for one person, the credits and what each came from | Commitment visible to the viewer (above); per-person rows filtered as the /commitments progress table and the person's commitments tab do |

## 8. Call log

Migration (fork, reversible, primary DB): `mcp_tool_calls` with `id` uuid, `user_id` uuid (FK), `oauth_application_id` (FK, nullable), `tool` string, `arguments` jsonb, `outcome` string (`ok`, `error`, `denied`), `error_message` string, `changed_type` string, `changed_id` uuid, `duration_ms` integer, `created_at`. Index on `created_at` and `user_id`. Model `McpToolCall`, `neat_ids` prefix `mcpc_`.

This marks writes as made through MCP (PaperTrail's `versions` table has no column for it, and it is in the other DB; join by `changed_type`/`changed_id` and time). It also answers which tools get used, the pitch's first step.

`arguments` stores the input as given. Read calls are logged too.

Page: `/mcp/calls`, admin only (`McpToolCallPolicy < AdminPolicy`), newest first, filter by user and tool, paginated like other index pages, linked from the feature's setup item. Retention: a recurring job is out of scope; note it in the backlog.

## 9. Upstream files touched

- `config/routes.rb`: one block in the `oauth_provider` section (no route seam).
- `Gemfile` (+ regenerated `Gemfile.lock`).
- `config/initializers/doorkeeper.rb` only if §4.1's runtime scope registration doesn't work.
- `db/schema.rb`: regenerated, the new table only (schema hygiene in `fork-feature`).

Connector branches touch no upstream files of their own.

## 10. Hooks

None. `McpToolCall` is a log, not something to react to; and writes go through the existing models (`BadgeAssignment`, `Membership`, `Checkin`, `Event`, `Signup`), which already fire their `CanBeHooked` events, so hooks run the same as for changes made on a page. Check that those models `include CanBeHooked` and appear in the hook catalog; report drift, don't fix it on this branch.

## 11. Client setup (for the help text and FORK.md)

1. Admin turns on OAuth provider and MCP server, sets the allowed badge, leaves writes off.
2. Admin creates an OAuth application: redirect URI from the client (claude.ai custom connectors use `https://claude.ai/api/mcp/auth_callback`; Claude Code uses a localhost callback port), scopes `mcp_read` (and `mcp_write` later), confidential for claude.ai, non-confidential (public, PKCE) for desktop and CLI clients.
3. Member adds the connector: URL `https://<host>/mcp`, client ID and secret from step 2 (claude.ai: advanced settings of a custom connector; Claude Code: `claude mcp add --transport http gatherpack https://<host>/mcp --client-id … --client-secret`). Confirm these against current client docs when writing help text.
4. Member approves on GatherPack's consent page. Revoking the application or the token ends access.

## 12. Tests

Minitest, fork world helpers (`test/support/*_world.rb`), `with_settings`, `with_feature`. Requests go to `/mcp` with a Doorkeeper token created in the test (`Doorkeeper::AccessToken.create!(resource_owner_id:, application:, scopes:)`).

- **Transport and access** (`test/controllers/mcp_controller_test.rb`): no token → 401 with `resource_metadata`; non-MCP scope → 403 `insufficient_scope`; feature off → 404; badge limit (holder allowed, non-holder and admin non-holder refused); `tools/list` with `mcp_read` lists no write tools; with `mcp_write` but `mcp_write_enabled` off lists none; a write tool called with a read token is refused even if named directly; `initialize` round trip; whodunnit on a write is the token's user; call log row per call.
- **Metadata and PKCE** (`test/controllers/mcp/metadata_controller_test.rb`, `test/integration/mcp_pkce_test.rb`): documents' fields and 404 when off; MCP authorization without PKCE refused, with S256 accepted, non-MCP authorization without PKCE unchanged.
- **Every tool** (`test/models/mcp/tools/<tool>_test.rb`, calling the tool class with a context): as an admin, a team manager, a plain member on another team, and a guardian of a member: what each sees or can change. At least one case per tool where a low-privilege user gets "Not found"/"Not allowed" or a filtered list. Connector tools add their own roles (badge-granted form coordinator, sheet organizer, commitment organizer).
- **Registry**: duplicate name raises; disabled feature's tools are neither listed nor callable.
- RuboCop clean; Brakeman no new warnings.

## 13. Phases

| Phase | Branch | Delivers |
|---|---|---|
| 1 | `feature/mcp` | Flag, settings, scopes, PKCE, metadata, transport, registry, `Mcp::Tool`/`Context`, call log and page, `whoami` and `search_people` with full tests |
| 2 | `feature/mcp` | Remaining core read tools (§7.1) |
| 3 | connectors | §7.3, §7.4, §7.5 read tools, §7.6, in parallel (disjoint branches) |
| 4 | `feature/mcp`, `feature/mcp-signups` | Write tools (§7.2, §7.5 writes) |
| 5 | hbr/platform | `fork/catalog.yml` entries, `fork/sample_data/features/mcp.rb` (an OAuth application with MCP scopes, flag on, allowed badge set, a few call log rows), FORK.md rows, manifest lines (with the fork owner's approval) |

Adoption order follows the pitch's first step: release with writes off and the badge limit set; turn writes on later by setting, no new build needed.

## 14. Open questions

1. Should the badge limit exempt admins? This spec says no (simpler trial). Change only if asked.
2. Retention for `mcp_tool_calls` (backlog item).
3. Whether to propose `feature/mcp` upstream. It depends on nothing fork-only; decide after the trial.
