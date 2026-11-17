# MCP server

## Summary

GatherPack serves a Model Context Protocol (MCP) endpoint, so a user's
AI client (claude.ai, Claude Desktop, Claude Code) can read and change
GatherPack data by being asked: "who on the build team hasn't turned in
the travel form?", "which open shifts are left at Saturday's outreach
event?", "how many hours does each family still owe?", "give the season
badge to these six people". The user connects the client once through
GatherPack's OAuth sign-in. Every tool runs as that user, within that
user's permissions. GatherPack holds no model API key and stores no
conversations.

## Problem

Most admin questions span several pages: a form's responses, a sign-up
sheet, a commitments balance, check-in history, badges. Answering one
means opening each page, running a report, or exporting to a
spreadsheet. Repeated small edits (badges, memberships, slot
placements) are one form per person.

The fastest path today is a coding agent running `rails runner` on the
server. That ignores every permission check, needs shell access, and is
available to one person. An MCP server gives the same reach to any
member with a client, limited to what that member may already see and
do.

## What it does

- **Connect.** The user adds the GatherPack URL as a connector. The
  client opens GatherPack's OAuth consent page, the user approves read
  or read-and-write access, and the client receives a token for that
  account. Revoking the application or token ends access.
- **Read tools.**
  - People: search, profile, person fields the user may read (including
    guardian-visible fields), teams, badges, guardianships.
  - Forms: who has and hasn't submitted, answers the user may see.
  - Sign-ups: sheets, open and filled slots, who signed up for what.
  - Commitments: progress and balance per person or family, and what
    each credit came from.
  - Time: check-ins, time clock hours for a person, team or date range,
    who is clocked in now.
  - Events and the ledger: events and attendees, balances and entries.
- **Write tools.** Assign or remove a badge, add or remove a team
  membership, place or remove a person on a sign-up slot, record a
  check-in, create an event. Each write takes explicit record IDs,
  changes one thing, and is recorded in the audit history as the user,
  marked as made through MCP in the call log.
- **Limits.** Off by default. An admin can allow it for everyone or only
  for holders of a badge, and can allow read tools only. No tool runs or
  edits reports, hooks or pages, sends messages, or changes settings,
  roles or gateways.

## How it is built

- **Feature.** Flag `feature_mcp`, off by default, registered with
  `Settings.register` from `config/initializers/mcp.rb`, with settings
  for the allowed badge and for write access. Requires the
  `oauth_provider` feature.
- **Transport.** One controller serving MCP's Streamable HTTP transport
  at `/mcp`, built on the official Ruby MCP SDK. It authenticates with
  `doorkeeper_authorize!` like `Api::V1::UserInfoController`, and sets
  PaperTrail `whodunnit` to the token's user.
- **Sign-in discovery.** The OAuth metadata documents MCP clients read
  to find the consent page, generated from the Doorkeeper configuration.
  PKCE required. Clients use a pre-registered OAuth application created
  on the OAuth Applications page; no dynamic client registration.
- **Scopes.** `mcp_read` and `mcp_write`, so a client can be limited to
  reading.
- **Tools.** One small class per tool: an input schema, a required
  scope, and a body that loads records with `policy_scope`, checks them
  with `authorize`, and filters person fields with
  `PersonField#readable_by?`. Tools do their own checks and never rely on
  a controller having done them. Reports and pages are not called; a
  tool that answers the same question queries the models directly.
- **Registry.** `Mcp.register_tool`, in the style of
  `Commitments.register_source` and `GatherPack::HookCatalog`. Person
  fields, forms, sign-ups and commitments each register their tools from
  their own initializers, and a disabled feature exposes none.
- **Call log.** Every tool call is recorded (user, application, tool,
  arguments, outcome, record changed) on an admin page. This is what
  marks a change as made through MCP, and shows which tools are used.
- **Tests.** For every tool, what an admin, a badge-granted coordinator,
  a member and a guardian can and cannot see or change; that a read
  token cannot call write tools; that the badge limit holds.

Upstream files touched: `config/routes.rb` (no route seam),
`Gemfile`, and `config/initializers/doorkeeper.rb` only if the scopes
can't be added from the feature's initializer. One migration (the call
log).

Size: read tools with transport, sign-in and tests, a few days. Write
tools, about a week more.

## Risks

- **Permissions.** The policies are the source of truth, and each tool
  must call them. A test as a low-privilege user is required for every
  tool before it is registered.
- **Text from members reaches the model.** Profile fields, form answers
  and notes are returned to the client and could contain instructions.
  One-change-per-call writes with explicit IDs let the client show the
  user each change before making it.
- **Data leaves the server.** Tool results, including data about minors
  and guardianships, go to the model provider the user's client uses.
  Enabling it for real member data needs a decision by the organization
  and a line in its data policy. The badge limit and read-only setting
  support starting small.

## First step

Read tools only, allowed for one badge, used by a few admins for some
weeks to learn which tools matter before adding write tools.
