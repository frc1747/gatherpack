# Sign-ups and commitments

## Summary

Two features that are often wanted together but stand on their own.
Sign-up sheets let people claim places at events: shifts to work or
items to bring, with caps and rules about who may take each one.
Commitments track what people owe ("3 shifts this season", "5 outreach
events") and count credit from check-ins and, when both are installed,
from sign-ups. Sign-ups don't depend on commitments, and commitments can
be adopted alone.

## Problem

Groups that run events on volunteer help handle these with outside
sign-up sites, spreadsheets, and group chats:

- **Staffing.** A snack-stand rota across a season of games needs a set
  number of people per game, some roles need a badge or a minimum age,
  and a parent often works a shift for their child. Outside sites know
  nothing about badges, ages, teams, or families, so organizers check by
  hand.
- **Bringing things.** A potluck or supply list ("6 pizzas, 2 dozen
  cookies") needs a quantity tracked against what is still needed, and
  someone to note what actually arrived.
- **Quotas.** "Each family works 3 shifts" or "attend 5 outreach
  events" is tallied by hand from sign-up exports and attendance, with
  siblings counted together and exceptions kept in someone's head.

The people, teams, badges, events, and check-ins all exist in GatherPack
already; the sign-ups and the tallies live somewhere else.

## What it does

Sign-up sheets:

- **Sheets, positions, slots.** A sheet belongs to a team and offers
  positions at a set of events. A position is either people to work
  ("Cashier", 3 places) or items to bring ("Main dish", 6 in "pans"),
  with an optional question ("What are you bringing?"). Each position at
  each event is a slot; a slot can change the cap or be turned off.
- **Eligibility rules** per position: any of a list of badges, an age
  range on the event date, or membership in any of a list of teams. A
  person who doesn't qualify sees why. Organizers can place anyone; the
  roster flags it.
- **Signing up for others.** A sheet can let a person sign up related
  people (a guardian for a child), and record a place as taken on
  behalf of someone else (a parent working a child's shift).
- **Audience** from teams and badges, with exclusions, the same shape
  as forms. A setting picks who sees names on the sheet.
- **Events.** Add dates creates events in bulk; a date whose time isn't
  known yet can be set later, and everyone signed up is told. The event
  page shows a sign-ups panel. Checking in to an event fulfils that
  person's shifts there; organizers mark items brought.
- **Organizers** are people holding a badge chosen in settings, each
  limited to a branch of the team tree, so volunteers can run a sheet
  without being made team managers. They see only that sheet's roster,
  and can't approve themselves or their relatives.
- **Notices** by email: confirmation, a reminder a set number of days
  before, changes of time, and organizer cancels and moves. Organizers
  can message everyone on a date without seeing addresses.

Commitments:

- **Who owes, how much, by when.** A team, optionally narrowed to a
  badge, minus holders of an exempt badge; an amount in a unit
  ("shifts", "events"); a date range; and whether planned or only
  confirmed activity completes it.
- **Credit sources**, in order, each with a ratio and an optional cap,
  so 3 sessions can make exactly 1 shift. Check-ins at an event type
  are built in; other kinds register themselves. One person at one
  event counts once, whichever sources see it.
- **Groups.** People connected through a relationship type, such as
  siblings through a parent, owe together: a set amount for the first
  member and a second, per-member amount for each other member, with
  everyone's credit pooled.
- **Adjustments** with a reason for the cases that don't fit.
- **Progress pages.** People see what they owe and how to earn it;
  organizers see one row per person or group with owed, confirmed,
  planned, and remaining, and can filter, print, and message those still
  open. Reports and other features ask `Commitment#progress_for`.

Together, a sheet or one position on it becomes a credit source, and
the sign-up dialog shows how much each on-behalf-of choice still owes.

## How it's built

Three branches, mostly new files:

- **Sign-ups:** about 120 files, 11 reversible migrations, all new
  tables. Five existing upstream files: one association on `Event`, one
  `render` line on the event page, feature registration, routes, and the
  schema.
- **Commitments:** about 60 files, 5 reversible migrations, all new
  tables. Three existing upstream files: feature registration, routes,
  and the schema.
- **Sign-up credit:** about 10 new files, no migrations, no upstream
  edits. The only code that knows both features.
- Each feature has its own flag, off by default; sign-up credit works
  when both are on.
- **Needs the extension registries change:** four upstream files that
  let a feature register its own settings and hook events from its own
  initializer, instead of every feature editing `lib/settings.rb` and
  `Hook.catalog`. No behavior change until something registers.

## Adoption

Extension registries first, as a small infrastructure PR. Then sign-ups
and commitments in either order, or only one of them, as feature PRs;
sign-up credit follows once both are in. A dashboard widget and a
commitments tab on the profile would use the widget and profile-tab
extension points if those exist.

Not built yet: a completion badge for a met commitment (reports read
progress instead), shift times within one event, per-person limits,
waiting lists, and self-reported hours.
