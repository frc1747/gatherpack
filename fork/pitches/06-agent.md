# AI agent

Status: idea, not built. Written 2026-10-31 to come back to later.

## Summary

Let people do GatherPack work by asking for it ("who on the build team
hasn't checked in since September?", "add the drive team badge to these
six people", "how many shift hours does each family still owe?") instead
of finding the right page and form. Start with GatherPack exposing its
data and actions as tools that an outside Claude client can call as the
signed-in user; optionally add a chat panel inside the app later.

## Problem

Much of the admin work in GatherPack is lookups across several pages and
repeated small edits: badges, memberships, check-ins, hours, sign-ups,
ledger questions. Today the fastest path for an admin who is comfortable
with code is a coding agent running `rails runner` against the database.
That works, but it ignores every permission check, needs shell access to
the server, and is unavailable to anyone else. An agent that is part of
the application could do the same work for anyone, but only within
their own permissions.

## What it would do

Two shapes, sharing one set of tools:

- **A. MCP server (start here).** GatherPack serves an MCP endpoint.
  Users connect claude.ai, Claude Desktop or Claude Code to it through
  the existing OAuth provider (Doorkeeper, behind the `oauth_provider`
  feature, already serving `api/v1`). Every tool runs as that user. No
  chat UI, no API key or billing inside GatherPack.
- **B. In-app chat.** A chat panel (Turbo Streams), a SolidQueue job that
  runs the tool loop with the Anthropic Ruby SDK, conversation tables,
  and settings for the API key, model and a monthly spending cap. For
  members who will never set up an MCP client.

Tools, read-only first: people, teams, badges, events, check-ins, time
clock hours, sign-ups, commitments progress, ledger balances. Then write
tools: assign or remove badges and memberships, record check-ins, place
people on sign-up slots, create events.

## How it would be built

- A `feature/agent` branch with flag `feature_agent`, off by default.
  An initializer registers the feature and its settings.
- A tool registry (`Agent.register_tool`), in the style of
  `Commitments.register_source`, so signups, commitments, forms and
  kiosk each add their own tools from their own initializers.
- Each tool loads records with `policy_scope` and checks them with
  `authorize`, and gets tests that check what each kind of user can and
  can't do.
- Routes are an upstream edit to `config/routes.rb` (no route seam yet;
  see the README's extension points).

Rough size: read-only MCP server, a few days. Write tools with
confirmation, audit tagging and permission tests, about a week. In-app
chat, another 1-2 weeks.

## Risks to design for

- **Permissions are not enforced by default.** `ApplicationPolicy`
  allows every action unless a policy says otherwise, and controllers
  that inherit `ApplicationController` skip `verify_authorized`. Tools
  can't assume the existing controllers did the checking. The
  `team_id: ""` scope bug in `EventPolicy` and `PagePolicy` also hides
  team-less events from non-admins.
- **No code execution.** Reports and hooks `eval` code and pages render
  ERB. The agent must never write or run any of them; otherwise anyone
  who can get text in front of it can run code on the server.
- **Prompt injection.** Tools return text that users wrote (person
  fields, form answers, page content, notes). Write tools should propose
  a change and wait for the person to confirm it.
- **Audit.** Set PaperTrail `whodunnit` to the real user (not the
  impersonated one), mark changes made through the agent, and set the
  `created_by` attributes writes require.
- **Privacy.** Tool results, including data about minors and
  guardianships, go to a third-party model API. This needs a decision
  from the organization and a line in its data policy before real member
  data is used. It is not a code question.

## Adoption

Upstream might accept the MCP server, since it is generic and builds on
their OAuth provider; pitch that alone. The in-app chat (B) would likely
stay fork-only, like widgets.

Suggested first step: a read-only MCP server, used by one admin for a few
weeks to learn which tools matter before building write tools or a chat
UI.
