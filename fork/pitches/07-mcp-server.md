# MCP server

## Summary

GatherPack serves a Model Context Protocol (MCP) endpoint, so an AI
client such as claude.ai, Claude Desktop, Claude Code or ChatGPT can
read and change GatherPack data on a user's behalf. The user connects
the client once through GatherPack's own OAuth sign-in. Every tool call
runs as that user, with that user's permissions. GatherPack holds no
model API key, pays for no model usage and stores no conversations.

## Problem

Much administrative work is a question that spans several pages ("who
on the build team hasn't checked in since September?", "which members
of the drive team are missing the safety badge?", "what does each
family still owe?") or a small edit repeated for a list of people. Doing
it means visiting each page, running a report, or exporting to a
spreadsheet. Organizations that want an assistant to help today must
give it direct database or server access, which bypasses every
permission check and is limited to whoever runs the server.

Users already have AI clients. MCP is the standard way for those clients
to reach an application's data, and GatherPack already has most of what
an MCP server needs: an OAuth provider, scopes, and Pundit policies.

## What it does

- **Connect.** A user adds the GatherPack URL as a connector in their
  client. The client sends them to GatherPack's normal OAuth consent
  page, they approve the requested scopes, and the client receives a
  token tied to their account. Revoking the application or the token
  ends access.
- **Read tools.** Search people and view a profile; list teams and
  members; list badges and who holds them; list events and their
  attendees; check-ins and time clock hours for a person, team or date
  range; ledger balances and entries. Each tool returns only what the
  user could see in the web interface.
- **Write tools.** Assign or remove a badge, add or remove a team
  membership, record a check-in, create an event. Each write is recorded
  in the audit log as the user, marked as made through MCP.
- **Scopes.** New OAuth scopes (`mcp_read`, `mcp_write`) let a user give
  a client read-only access, and let an admin limit which OAuth
  applications may request write access.
- **Admin control.** The server is a feature that can be turned off in
  Setup, and is off by default. Admins see connected MCP clients on the
  existing OAuth Applications page.

What the server does not do: run or edit reports, hooks or pages, or
anything else that evaluates code; send messages or email; change
settings, roles or gateways.

## How it is built

Mostly new files, on top of upstream's existing pieces:

- **Transport.** One controller serving MCP's Streamable HTTP
  transport at `/mcp`, using the official Ruby MCP SDK (`mcp` gem).
  It authenticates with `doorkeeper_authorize!`, like
  `Api::V1::UserInfoController`, and sets the acting user and PaperTrail
  `whodunnit` from the token's resource owner.
- **Discovery.** The metadata documents MCP clients use to find the
  sign-in: OAuth Protected Resource Metadata at
  `/.well-known/oauth-protected-resource` and Authorization Server
  Metadata at `/.well-known/oauth-authorization-server`, both generated
  from the Doorkeeper configuration. PKCE is required for MCP
  applications. Clients that need a pre-registered client ID use one
  created on the OAuth Applications page; dynamic client registration
  is optional, off by default.
- **Tools.** One small class per tool, each with an input schema, a
  required scope, and a body that loads records through `policy_scope`
  and checks them with `authorize` using the existing policies. Tools
  do their own authorization rather than relying on a controller.
  Results use the same attributes the web pages show.
- **Registry.** `GatherPack::Mcp.register_tool`, called from
  initializers, so each feature registers its tools and only enabled
  features expose them. Plugins add tools the same way, in the style of
  `GatherPack::Features.register`.
- **Feature.** An `mcp_server` entry in `config/initializers/features.rb`,
  default off, which requires `oauth_provider`.
- **Tests.** For each tool, what an admin, a team lead and an ordinary
  member can and cannot see or change, and that a read-only token
  cannot call write tools.

Upstream files touched: `config/routes.rb` (the `/mcp` and
`.well-known` routes inside the existing `oauth_provider` block),
`config/initializers/doorkeeper.rb` (new scopes, PKCE),
`config/initializers/features.rb` (the feature entry), the Doorkeeper
scope locale strings, and `Gemfile`.

Size: medium, mostly new files. Read tools with transport, discovery
and tests are the bulk of the work; write tools follow the same pattern.
No migrations, unless the audit-log marker needs a column.

## Design notes

- **Permission checks belong in each tool.** The policies are the
  source of truth, and a tool must call them explicitly. A tool test
  that runs as a low-privilege user is required for every tool.
- **User-written text reaches the model.** Profile fields, page content
  and notes are returned to the client. Write tools should take explicit
  record IDs and change one thing per call, so the client can show the
  user what it is about to do before it does it.
- **Data leaves the server.** Tool results go to whichever model the
  user's client uses. Organizations that serve minors may want to limit
  the feature to admins or to read tools. The feature flag and the
  scopes support that; the decision is the organization's.

## Adoption

The server is generic: it serves any GatherPack organization and any
MCP client, and builds on the OAuth provider and policies already in
core. It can be adopted in two steps: first the transport, discovery,
registry and read tools; then write tools once the read tools have been
used for a while. Features outside core (forms, sign-ups, kiosk)
register their own tools through the registry and need no changes to
the server.
