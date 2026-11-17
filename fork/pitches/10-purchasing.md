# Purchasing and inventory

## Summary

Let members ask for things to be bought, have the right people approve
them, record what was bought and from where, and confirm it arrived, all
inside GatherPack and from a phone. A separate inventory layer keeps track
of what an organization owns and where it is, including reusable parts that
move between machines. The two work alone, and connect when both are on:
low stock becomes a request, and what arrives goes back on the shelf.

## Problem

Groups that buy things for their members, such as robotics teams, scout
troops, booster clubs and community workshops, usually run purchasing
through a shared form and a spreadsheet. The form collects a link and a
name, and everything after that happens in email and in someone's head:

- **Nobody knows what a request is waiting on.** Is it approved? Ordered?
  Lost? The person who asked has to chase someone to find out.
- **Approval rules live outside the tool.** "Over $500 needs the treasurer"
  is a habit, not a check, and the approver can't see what the budget has
  left.
- **Buying and paying are disconnected.** One order often covers several
  requests, the price at checkout differs from the request, someone pays
  with their own card and needs paying back, and part of it is backordered.
  A spreadsheet row can't hold that.
- **Restricted money is hard to track.** A grant "for robot parts only"
  needs a list of what it bought, with receipts, at the end of the year.
- **Stock is invisible.** People buy what is already in a cabinet, or find
  out a part is gone when they need it. Reusable parts, such as motors that
  come off one robot and go onto another, have no history, so a worn or
  broken one goes back into service.

## What it does

**Order requests.**

- A member starts a request on a phone by pasting or sharing a link, or
  with a photo and a description when there is no link. A request can have
  several lines from several stores, and "Not sure" is a valid answer for
  where to buy something.
- Approval follows steps the organization sets, with amount thresholds
  ("from $500, the treasurer too"). Approvers can approve, decline or ask
  for changes, and see what the funding source has left.
- Buyers combine approved lines from several requests into one purchase,
  record the actual price (small differences within a set tolerance need
  no new approval), mark backorders and split deliveries, and note who
  paid and whether they need paying back.
- Whoever receives an item marks it arrived, all at once or a few at a
  time. Damaged or wrong items become a problem for a buyer to settle.
- Every request shows plainly what it is waiting on and who has it, with
  a timeline of everything that happened.
- Funding sources (budgets, grants, gifts) can have an amount and a
  restriction. Approvers confirm a request fits a restriction, and a report
  lists what each source bought. When the Ledger and Budgets features are
  on, a purchase can be recorded in a ledger against a budget.
- Notices go out as a daily digest by default, with urgent ones sent right
  away, and each person chooses what they get.

**Inventory.**

- Items are kept by place: rooms, cabinets, bins, carts and machines.
  People record what they used, moved or counted, with a phone-sized
  screen and printable shelf labels with a code to scan.
- A Reorder page lists what is running low or out, and what is already on
  order.
- Reusable parts can be tracked one by one: each has a condition (new,
  good, worn, needs repair, broken, retired), readings such as a battery's
  charge cycles, and a history of the machines it was installed on.
  Machines can hold sub-assemblies, such as a module with two motors.

**Together.** "Order these" on the Reorder page turns low items into a
draft request with each item's usual store filled in. Receiving an order
puts the items on the shelf they belong on, and tracked parts arrive as new
units ready to label.

Both layers have phone-first screens, appear on the home page as to-dos
for the people who act on them, and can be used from an AI client through
the MCP server, within the member's permissions.

## How it's built

- **Mostly new files.** Orders adds eleven tables and inventory seven,
  each in its own migrations; the connecting layer adds one column. The
  only upstream edits are one line on the dashboard and one on the ledger
  entry page, plus a QR code gem for shelf labels.
- **Settings, not code, for each organization's rules.** Who can request,
  the approval steps and thresholds, buyers, price tolerance and payment
  choices are all settings. Permissions reuse badges and team management,
  scoped to the teams a person reaches.
- **Every change goes through one place.** Request state changes are
  recorded as append-only timeline events, and every stock change is a
  movement record, so counts and history can't drift apart, and undo is
  just another movement.
- **Extension points.** The Reorder page accepts actions from other
  features (printing and the CSV export are built this way, and so is
  "Order these"). Hooks fire when a request or line changes status, when
  an item runs low, runs out or is restocked, when a count finds a
  difference, and when a tracked part is installed, removed or needs
  repair.
- **Flags off by default**, one for orders and one for inventory.

## Risks

- **Scope.** Purchasing touches money, so mistakes are costly. The design
  keeps the books out: it records what was bought from which source and
  can write a ledger entry, but it isn't accounting software.
- **Approval rules vary widely.** Steps with thresholds cover the common
  cases; anything stranger becomes a setting or an extension point, not a
  special case in the code.
- **Store links.** Filling in the store and part number from a link
  depends on what each store's page exposes, so it is best-effort and never
  required.

## First step

Order requests alone, with plain "it arrived" receiving, replace the form
and spreadsheet. Inventory and the connection between them can follow.

## Adoption

Requires the extension registries (settings, hook catalog and feature
registration) and the routes and recurring-job seams. Orders and inventory
are independent of each other and of the other features here. The ledger
connection uses the existing Ledger and Budgets features when they are on
and is skipped when they are off.
