---
name: fork-spec
description: Write or revise HBR fork specs, pitches, backlog items and task briefs, and design screens - what a spec contains, decision rules, UI and copy conventions the fork owner expects. Use before writing anything in fork/specs, fork/pitches, fork/backlog or tasks/, and before designing a new screen.
---

# Specs, pitches, backlog and screen design

## Where things go

| Kind | Place | Contains |
|---|---|---|
| Spec | `fork/specs/<feature>-spec.md` | The design a worker builds from. |
| Pitch | `fork/pitches/NN-<slug>.md` (+ README index) | Feature ideas, built or not. Check the index first: if a pitch covers the idea, say so instead of writing a new one. |
| Backlog item | `fork/backlog/BL-NNN-<slug>.md` + README index row | Bugs and tasks found but not started, detailed enough to pick up cold: evidence (upstream commit + line numbers), proposed fix, tests, fork notes. Items that would reveal an unreleased security fix go in the local private backlog (`notes/private-backlog/SBL-NNN`) instead. When an item gets a branch, it moves to `FORK.md`; remove shipped items. |
| Task brief | `~/dev/gatherpack/tasks/NNN-slug.md` (never committed) | From `fork/claude/task-template.md`. |

All of these except task briefs are pushed straight to `hbr/platform`.

## Rules for every document

- **Decide, don't ask.** No "open questions" or "decisions for the owner" lists. Pick the sensible default and record it as a decision; where organizations could reasonably differ, make it a setting with that default. Brief designer agents the same way.
- **No timing.** No dates, phase deadlines, freezes or release targets: order and dependencies only. Dates that are configuration data (a commitment's due date) are fine.
- **Start with what it does.** No status, branch, spec-link or "meant for upstream" headers, and no upstream intent unless the owner said so for that feature. Pitches describe only the feature: summary, problem, what it does, how it's built, adoption options. No "we/our", no people's names.
- **No real names.** Describe people by role ("a couple signing up together"). Sample data and mockups use the Northwind made-up people.
- **Generic layers, team as configuration.** No team-specific words or concepts in code or specs. A word like "Machine" becomes configurable on the feature's Setup page (rename it, turn it off), everywhere it appears: menus, pages, messages, MCP descriptions, notices. Picture a 4-H club or a scout troop using the feature.
- **Hooks section** in every spec (see `fork-feature`).

## Screen design

- **Copy:** directions say what to do, in order, in one or two plain sentences, with a concrete example when the use isn't obvious. No abstract taglines ("little wisps of AI garbage") or insider terms ("basis", "intent", "on file"). Label fields by the question they answer ("Who to include", "Columns"). Button words shouldn't sound permanent when the action is safe ("Take Snapshot", not "Record this list").
- **Name features for what they do in general**, not after the first use case.
- **Start from the thing the page is about**, then plain radio choices with their settings inline; progressive pickers that reveal without a reload; tick boxes over multi-selects; one general option over several special cases.
- **Warnings sit by the action:** a short question just above Save with inline choices (safe default selected), applied by the save. No page-top alerts with immediate-action buttons.
- **Several choices mean "any of".** When a screen lets someone add more than one team, badge or rule of a kind, the model must treat them the way the screen reads (normally any-of), or the screen must block a second one. Say it on screen ("Any of these teams").
- **Signed up is not done.** Planned or signed-up records go under their own **Upcoming** heading (soonest first), apart from **Done** (confirmed only, newest first); "Still open" is a third list.
- **Status words** default to Complete / In Progress / Not Started, and can be overridden per checklist and per item. Don't argue finer distinctions against plain words the owner picks.
- **Guardian parts only when a guardian is reached:** split counts and wording into "themselves" and "guardians" only when the real recipients include guardians. Steer guardians with wording, not new permission settings.
- **Native over config:** surface a feature the way the nearest existing feature does (native card, profile tab), even if that costs a one-line `render` in an upstream view (recorded in `FORK.md`). Never a second mechanism such as an admin-built widget.
- **Match upstream's look:** copy the nearest upstream screen. Buttons follow gp-map "Views" (full-size solid; outline only for small row buttons, toggle groups, My GatherPack card secondary actions).
- Don't use demo data that makes a feature look pointless.

## Defined things (types, units, conditions, categories)

AGENT.md rule 13. The standard way (Jira issue types and statuses, Salesforce picklists, Odoo units of measure, and upstream's own Team Types, Badge Types, Event Types, Relationship Types and Check-in Fields) is a small table managed on a screen:

- **A table per vocabulary**, not a setting: `name` (and `plural` when the word is shown as a count), `position` for order, `active` (retire instead of delete), optional `description`, `color`/`icon` when the screen shows them, and `team_id` only if teams really differ.
- **Records point at it by id**, so renaming a row renames it everywhere. Never store the word on the record.
- **Behavior is a flag on the row, not a reserved name.** A location type that holds installed parts has `holds_installed_parts: true`; code reads the flag. If code needs one specific row, give it a stable `key` that the admin can't change, and let the label change freely.
- **Defaults are rows, not code.** A data migration (reversible) and the seeds create the starting rows (e.g. units: each, box, pack, ft, m; conditions: New, Good, Worn, Needs repair, Broken, Retired). Existing text values are converted into rows and linked, never dropped.
- **Remove safely:** a row in use can't be deleted, only retired (hidden from pickers, still shown on old records), or merged into another row.
- **Where it's managed:** a button on the main Setup page under the feature's heading (as upstream's types are), listing rows with Add, Edit, drag or arrows to reorder, Retire. Pickers on other screens offer the active rows and a "Manage <things>" link for admins.
- **Settings stay for single choices about behavior** (on/off, how often, a number), never for lists of things people define.
- Hooks: these tables usually aren't hooked; say so in the spec's Hooks section.
