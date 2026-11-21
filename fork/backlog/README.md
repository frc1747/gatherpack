# HBR Backlog

Work we've found and decided to do later. These are usually upstream bugs or improvements we're holding back so Brad can work through what we've already sent him. Each item has its own file in this folder with enough detail to pick it up cold: what's wrong, how we know, the fix we have in mind, how to test it, and how it fits the fork strategy.

Once an item has a branch, [`FORK.md`](../../FORK.md) tracks the branch and the item's file links to it. The status here says where the work stands: `started` while it's being built, `live` once it's in our production but upstream hasn't taken it, then `done` or `shipped`.

## Items

**Up next**: [BL-046](BL-046-wrapped-checklist-exempt-people.md) once its decisions are made.

| ID | Title | Kind | Priority | Status | Added |
|---|---|---|---|---|---|
| [BL-001](BL-001-page-index-permissions.md) | Page list ignores the Viewer setting and leaks content previews | upstream bug (security) | high | shipped hbr.34 | 2026-10-03 |
| [BL-002](BL-002-period-hours-date-bounds.md) | Period hours skip meetings near the period's last day | upstream bug | low | live hbr.32 | 2026-10-03 |
| [BL-003](BL-003-attendance-eligibility-badge.md) | Keep a travel-eligibility badge in sync with attendance | fork-only | medium | blocked | 2026-10-03 |
| [BL-004](BL-004-version-in-sidebar.md) | Show the deployed version under "powered by GatherPack" | upstream feature | low | live hbr.6 | 2026-10-03 |
| [BL-005](BL-005-event-delete-with-checkins.md) | Deleting an event that has check-ins crashes | upstream bug | medium | live hbr.32 | 2026-10-04 |
| [BL-006](BL-006-team-less-events-hidden.md) | Events with no team are hidden from everyone but admins | upstream bug | medium | blocked | 2026-10-05 |
| [BL-007](BL-007-seeds-badge-before-membership.md) | First boot on a fresh database crashes in db/seeds.rb | upstream bug | medium | live hbr.32 | 2026-10-05 |
| [BL-008](BL-008-member-info-access.md) | Restrict Member Info: its own on/off switch, and managers only by default | upstream feature (security) | high | dropped | 2026-10-05 |
| [BL-009](BL-009-person-team-ids-return-records.md) | `Person#all_team_ids` and `#all_ancestor_team_ids` return Team records mixed with ids | upstream bug (latent) | low | live hbr.32 | 2026-10-06 |
| [BL-010](BL-010-long-tick-box-lists.md) | Keep long tick-box lists short on the printable list | fork-only | medium | shipped hbr.32 | 2026-10-07 |
| [BL-011](BL-011-accounting-integration.md) | Accounting integration (QuickBooks Online first) | fork-only | medium | waiting | 2026-10-07 |
| [BL-012](BL-012-kiosk-period-less-punch.md) | Time kiosk crashes for anyone with a punch that has no period | upstream bug | medium | live hbr.32 | 2026-10-08 |
| [BL-013](BL-013-settings-cached-per-process.md) | Saved settings reach only one server process until a restart | upstream bug | medium | done (upstream merged PR #544, 2026-11-09) | 2026-10-09 |
| [BL-014](BL-014-hook-catalog-drift.md) | Hook catalog misses models that fire hooks | upstream bug | low | live hbr.32 | 2026-10-09 |
| [BL-016](BL-016-inline-code-blanked.md) | Inline code in Markdown shows up as an empty code editor | upstream bug | low | live hbr.27 | 2026-10-10 |
| [BL-017](BL-017-event-time-tba-all-day.md) | Events with no known time: "Time TBA" and all-day events | upstream feature | low | live hbr.32 | 2026-10-11 |
| [BL-018](BL-018-settings-and-hook-registries.md) | Let features register their own settings and hook events | upstream feature | medium | live hbr.16 | 2026-10-11 |
| [BL-019](BL-019-blocked-deletes-error-page.md) | A delete the database refuses shows an error page | upstream bug | low | live hbr.32 | 2026-10-11 |
| [BL-022](BL-022-guardianship-grants-hint.md) | Say what guardianship grants, where it's set | upstream feature | medium | live hbr.32 | 2026-10-13 |
| [BL-023](BL-023-contact-relationships.md) | Emergency contacts without guardian powers | upstream feature | low | live hbr.32 | 2026-10-13 |
| [BL-024](BL-024-profile-hides-closed-teams.md) | Profiles hide the closed teams a person is in | upstream feature | low | live hbr.32 | 2026-10-13 |
| [BL-025](BL-025-drift-check-upstream-ci.md) | The drift check doesn't notice when upstream itself is broken | fork-only | medium | started | 2026-10-23 |
| [BL-026](BL-026-organizer-placements-look-like-yours.md) | Placing someone as an organizer looks like signing up yourself | upstream feature | medium | live hbr.32 | 2026-10-29 |
| [BL-027](BL-027-kiosk-period-clock-out-refused.md) | Kiosk "Clock Out" for one period silently does nothing for mentors | fork-only | medium | shipped hbr.34 | 2026-11-01 |
| [BL-028](BL-028-members-edit-own-punches.md) | Members can enter and change their own time clock punches by hand | upstream bug | medium | shipped hbr.34 | 2026-11-04 |
| [BL-029](BL-029-alert-flash-unstyled.md) | Error messages sent as `alert` show with no colour | upstream bug | low | live hbr.32 | 2026-11-04 |
| [BL-030](BL-030-refused-delete-audit-row.md) | A refused delete still writes a "destroy" audit entry | upstream bug | low | live hbr.32 | 2026-11-04 |
| [BL-031](BL-031-event-type-delete-checkin-fields.md) | Deleting an event type that has check-in fields crashes | upstream bug | low | live hbr.32 | 2026-11-04 |
| [BL-032](BL-032-event-type-change-checkin-fields.md) | Changing an event's type doesn't update its check-ins' fields | upstream bug | low | live hbr.32 | 2026-11-04 |
| [BL-033](BL-033-search-form-asterisks.md) | Search forms mark every field as required | upstream bug | low | live hbr.35 | 2026-11-08 |
| [BL-034](BL-034-table-responsive.md) | Three screens have wide tables that widen the page on a phone | upstream improvement | low | live hbr.35 | 2026-11-08 |
| [BL-035](BL-035-people-search-phone.md) | The People search form fills the phone screen | upstream improvement | medium | live hbr.35 | 2026-11-08 |
| [BL-036](BL-036-ransack-associations-allowlist.md) | Six admin list pages raise a Ransack allowlist error | upstream bug | medium | live hbr.23 | 2026-11-08 |
| [BL-037](BL-037-calendar-note-badge-args.md) | The calendar notes page crashes when a note links to a record | upstream bug | medium | live hbr.41 | 2026-11-08 |
| [BL-038](BL-038-kiosk-device-token.md) | Let a dedicated kiosk computer stay on the time clock without a user login | upstream feature | medium | new | 2026-11-09 |
| [BL-039](BL-039-kiosk-no-sign-out.md) | Take the Sign out button off the kiosk account's kiosk header | fork change | medium | new | 2026-11-09 |
| [BL-040](BL-040-kiosk-serial-scanner.md) | Read the kiosk's card scanner as a serial device instead of a keyboard | fork-only | low | waiting | 2026-11-10 |
| [BL-041](BL-041-count-done-hides-group-records.md) | A family member's credit counts toward a count item but isn't listed under Done | fork-only | medium | shipped hbr.39 | 2026-11-11 |
| [BL-042](BL-042-relationship-type-delete-breaks-count-item.md) | Deleting a relationship type that a count item pools through breaks the item | fork-only | low | shipped hbr.39 | 2026-11-11 |
| [BL-043](BL-043-checkin-answers-block-deletes.md) | Check-in fields and event types with stored answers can never be deleted | upstream bug | low | live hbr.32 | 2026-11-11 |
| [BL-044](BL-044-home-my-season-and-activity.md) | Home shows checklist math instead of answers; add a "My activity" page | fork-only (UX) | high | shipped hbr.41 | 2026-11-15 |
| [BL-045](BL-045-checklist-rule-wording.md) | "Finishes a checklist" reads as a reward, not a requirement; no warning for a catch-22 | fork-only (UX) | high | shipped hbr.41 | 2026-11-15 |
| [BL-046](BL-046-wrapped-checklist-exempt-people.md) | Checklists made from commitments treat an exempt badge as "not on the checklist" | fork-only (bug) | medium | blocked | 2026-11-15 |
| [BL-047](BL-047-orders-approval-fixes.md) | Order approval: repeated field ids, declined items say waiting, re-approval shows $0.00, plus three spec gaps | fork-only (bug) | medium | shipped hbr.42 | 2026-11-15 |
| [BL-048](BL-048-orders-inventory-polish.md) | Orders/inventory: new-request autosave refused (blocking), menu links members can't open, phone layout, import preview, notices link | fork-only (bug) | high | shipped hbr.42 | 2026-11-15 |
| [BL-049](BL-049-hbr42-docs-findings.md) | hbr.42 docs findings: activity "Counts toward" missing for sign-ups, To receive not in member menu, empty-looking ticks, filter wording, demo data | fork-only (bug) | medium | shipped hbr.43 | 2026-11-16 |
| [BL-050](BL-050-hbr45-docs-findings.md) | hbr.43-45 docs findings: settings missing from Orders/Inventory setup pages, picker wording, funding dates, search match, midnight events on Family and Home, demo kiosk setting | fork-only (bug) | high | shipped hbr.47 | 2026-11-17 |
| [BL-051](BL-051-admin-notice-flood.md) | Site admins get every team's approval, registration and join notices | fork-only | medium | waiting | 2026-11-17 |
| [BL-052](BL-052-email-rate-limit-retry.md) | Emails over the Resend rate limit fail and are never retried | upstream bug | medium | shipped hbr.50 | 2026-11-17 |
| [BL-053](BL-053-event-type-starts-locked.md) | Events members shouldn't check themselves in to must be locked one at a time; let an event type start its events locked | fork-only | medium | shipped hbr.50 | 2026-11-17 |
| [BL-054](BL-054-sent-email-log.md) | Sent email log: delivery, bounces and link clicks from the sending service, on an admin screen and on order requests | fork-only | medium | waiting | 2026-11-17 |
| [BL-055](BL-055-order-form-pinned-buttons.md) | Pinned Save/Cancel on every form (sticky button row), the standard Order Settings already uses | fork-only (UX) | medium | shipped hbr.51 | 2026-11-18 |
| [BL-056](BL-056-orders-inventory-email-choices.md) | Orders and Inventory emails: one model, a site default (each time, daily digest, Weekly Infodump, off) and each person's own choice | fork-only | high | shipped hbr.51 | 2026-11-18 |
| [BL-057](BL-057-orders-separate-roles.md) | Orders roles: requesting, approving and buying set separately by badge or team-manager grants; team managers no longer get all three (Inventory Managers too) | fork-only (security) | high | shipped hbr.51 | 2026-11-18 |
| [BL-058](BL-058-form-creator-audience-teams.md) | Form creators get an empty team picker on a form's Audience tab; let admins name other teams (e.g. Mentors) creators may ask | fork-only | medium | done (feature/forms) | 2026-11-19 |
| [BL-059](BL-059-checklist-reminders.md) | Checklist reminders by email (and to guardians), with a "keep out of email" rule on fields and checklists so protected records only say "sign in" | fork-only | medium | done (feature/checklists-reminders) | 2026-11-21 |
| [BL-060](BL-060-one-form-results-page.md) | One page for a form's responses: status, answers and totals (hideable) together, print/CSV from it; Taking answers becomes a plain choice in the form's setup; footer cut to Edit, Remind and a More menu | fork-only | medium | done (feature/forms) | 2026-11-21 |
| [BL-061](BL-061-screen-audit-and-standard.md) | Audit every screen (fork and upstream) by layer and audience, write one standard per screen kind (layout, button placement and words, state changes, where configuration lives), and plan the fix-up items | fork-only | high | done | 2026-11-21 |
| [BL-062](BL-062-screen-kit.md) | Screen kit: shared partials (header and state line, action row with More, inline confirm, filter bar, people table, tabs) and grey Cancel on upstream forms behind a flag; first of the screen fix-ups | fork-only (screens) | high | done (feature/screen-kit) | 2026-11-21 |
| [BL-063](BL-063-screens-home.md) | Home and My GatherPack screens to the screen standard (Hours footer into More, Activity filter, Family shifts row) | fork-only (screens) | high | done (my-gatherpack branches) | 2026-11-21 |
| [BL-064](BL-064-screens-forms.md) | Forms screens to the standard after BL-060: one job button and More on a response page, reminder and edit footers, forms list | fork-only (screens) | high | done (feature/forms) | 2026-11-21 |
| [BL-065](BL-065-screens-signups.md) | Sign-up sheets to the standard: Edit not "Set up", Taking sign-ups choice, setup tabs, "Cancel sign-up" for members | fork-only (screens) | high | done (feature/signups) | 2026-11-21 |
| [BL-066](BL-066-screens-checklists.md) | Checklists to the standard: header buttons to an action row with More, Counting choice, setup tabs | fork-only (screens) | high | done (feature/checklists) | 2026-11-21 |
| [BL-067](BL-067-screens-events.md) | Event page panels (forms, sign-ups) in one shape with one row button each | fork-only (screens) | medium | done (forms, signups) | 2026-11-21 |
| [BL-068](BL-068-screens-profiles.md) | Profile tabs (Forms, Checklists, Commitments) and intake's application rows to the standard | fork-only (screens) | medium | waiting | 2026-11-21 |
| [BL-069](BL-069-screens-orders.md) | Orders to the standard: one job button and More on a request, line actions in More, settings footer | fork-only (screens) | medium | done (feature/orders) | 2026-11-21 |
| [BL-070](BL-070-screens-commitments.md) | Commitments to the standard: Edit not "Set up", action row with More, setup tabs | fork-only (screens) | medium | done (feature/commitments) | 2026-11-21 |
| [BL-071](BL-071-screens-inventory.md) | Inventory to the standard: item and place pages with Edit, one job and More; no repeated list links; setup footer | fork-only (screens) | medium | done (feature/inventory) | 2026-11-21 |
| [BL-072](BL-072-screens-intake.md) | Intake leader pages: breadcrumbs, Taking registrations choice instead of "Close now", action row | fork-only (screens) | low | done (feature/intake) | 2026-11-21 |
| [BL-073](BL-073-screens-setup-only.md) | Setup-only fork screens (person fields, managed lists, housekeeping, widgets, merge, MCP log) to the standard | fork-only (screens) | low | done (setup-only branches) | 2026-11-21 |

## Fields

- **Kind**: `upstream bug`, `upstream feature`, `fork-only` (HBR config, tooling, or content that upstream wouldn't want), or `ops`. Add `(security)` when it exposes data or permissions.
- **Priority**: `high` (fix next time we have capacity; real harm), `medium` (worth doing), `low` (nice to have).
- **Status**:
  - `waiting`: ready to do, deliberately parked.
  - `blocked`: can't start yet; the item says on what.
  - `started`: has a branch, not yet in production; tracked in `FORK.md`.
  - `live hbr.N`: in our production since release `hbr.N`, waiting on upstream (the issue or PR isn't sent yet, or is still open). For upstream bugs and features only. When upstream merges it, it becomes `done`.
  - `shipped hbr.N`: fork-only work in production since `hbr.N`; nothing left to do. Keep the row and its file for one release cycle, then delete both.
  - `done`: upstream merged it or fixed it themselves. Keep the row and its file for one release cycle, then delete both.
  - `dropped`: decided against it. Record why in the item file.

## Adding an item

1. Copy the layout of an existing item into `BL-NNN-<slug>.md`, using the next number. Don't reuse numbers.
2. Add a row to the table above.
3. Write it for someone who has no memory of the conversation where it came up. Include file paths with line numbers *and* the upstream commit they refer to, since line numbers drift.
4. Leave out production data (names, emails, record contents). Counts and structure are fine.

## Picking up an item

1. Re-check the evidence against current `upstream/main`. Upstream may have fixed it already.
2. Follow [`STRATEGY.md`](../STRATEGY.md): branch from `upstream/main`, add a `FORK.md` row, and confirm with Corey before opening anything upstream.
3. Set the item's status to `started` and link the branch.
4. When a release first includes it, set the status to `live hbr.N` (upstream bug or feature) or `shipped hbr.N` (fork-only), in the table and the file.
