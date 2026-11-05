# Search and add

## Summary

A search panel beside four lists for adding people (or teams) in place,
one click each, instead of a form page and redirect per addition.

## Problem

On these screens, each addition means opening a form page, saving, being
redirected, and starting over for the next one:

- a badge's holders
- a team's members
- a person's teams
- an event's check-ins

Adding twenty members to a team takes twenty round trips through a form.

## What it does

- **Live search.** Results update while typing. Each result has an Add
  button, and the added person appears in the list without leaving the
  page.
- **Only valid choices.** Results include only people the user can see,
  and leave out anyone who already has the badge, is already on the team,
  or is already checked in. On a person's teams, results are teams the
  user manages that the person isn't on yet.
- **Errors on the row.** A failed add (for example, a full event) shows
  its message next to that result, not on a new page.
- **Existing forms unchanged.** The current pages and redirects still
  work; the panel sits beside them.
- **Indirect members labeled.** On a team's member grid, people listed
  without being direct members are marked "Via *child team*" or "Manager
  of *parent team*", with a link to where that membership is managed.
  Without the label they look like direct members that can't be removed.

## How it's built

- Shared by all four screens: a `SearchAndAdd` controller concern, three
  partials (`shared/_add_panel`, `_add_candidates`, `_add_candidate`), and
  an auto-submit Stimulus controller.
- Controllers return a Turbo Stream only when the panel requests one
  (through a `.turbo_stream` URL). All other form submissions keep their
  normal redirect.
- No migrations, settings, or feature flag. Uses `MembershipPolicy#create?`
  (PR #521) and the unique indexes from PR #522, both already upstream.

**Footprint:** about 20 new files. Edits to 10 existing files: the badge
assignments, check-ins, and memberships controllers and their list views,
`memberships_helper.rb`, `_cards.scss`, and `config/routes.rb` (candidate
search routes). Controller and system tests for all three areas.

## Adoption

Can be taken as one PR, or split by screen (badges, memberships,
check-ins) with the shared concern and partials first.
