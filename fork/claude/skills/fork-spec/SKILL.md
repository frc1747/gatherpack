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

- **Decide, don't ask.** No "open questions" or "decisions for the owner" lists. Pick the sensible default and record it as a decision. Make it a setting only where organizations really differ and no default fits most of them (see "Simple first" below). Brief designer agents the same way.
- **No timing.** No dates, phase deadlines, freezes or release targets: order and dependencies only. Dates that are configuration data (a commitment's due date) are fine.
- **Start with what it does.** No status, branch, spec-link or "meant for upstream" headers, and no upstream intent unless the owner said so for that feature. Pitches describe only the feature: summary, problem, what it does, how it's built, adoption options. No "we/our", no people's names.
- **No real names.** Describe people by role ("a couple signing up together"). Sample data and mockups use the Northwind made-up people.
- **Generic layers, team as configuration.** No team-specific words or concepts in code or specs. A word like "Machine" becomes configurable on the feature's Setup page (rename it, turn it off), everywhere it appears: menus, pages, messages, MCP descriptions, notices. Picture a 4-H club or a scout troop using the feature.
- **Hooks section** in every spec (see `fork-feature`).

## Screen design

Two principles come before every rule below.

**1. Consistency: every feature looks and works the same.** Someone who has learned one screen should already know the next.
- Same kind of screen, same layout: a list page, a record page, a setup page and a form each have one shape across all features (header card with title and one-line summary, filters, then the table or content, then actions). Before designing, find the nearest existing screen of the same kind, fork or upstream, and copy its layout, button order and words.
- Same action, same word, style and place: the words and styles are in gp-map "Views", the places in "The standard" below.
- Same pieces: status badges, filters, tick lists, empty states ("Nobody here."), the people table. If a feature needs one that doesn't exist, build it once as a shared partial and use it everywhere, rather than a near-copy.
- When a new screen and an old one disagree, fix the old one to match (or note it in the backlog), don't add a third style.

**2. Simple first: dead simple for people reading, flexible for people setting up.** Most people only consume information: members, guardians, readers of a report. Their screens show the answer, not the machinery.
- One screen per job. Don't split one list into status, results, totals and print views; show it once with sensible defaults, and let people hide parts they don't want (BL-060 is the pattern).
- At most three visible actions on a page; the rest go in a **More** menu.
- A control sits where the thing it changes is set up, not in a row of action buttons: whether a form takes answers is a choice on its setup page, next to its opening time and deadline.
- Nobody should have to guess what a control does. Say the effect in the control itself ("Taking answers: Not yet / Yes, open now / No, closed") and show the current state in words on the page ("Taking answers until Nov 30"), rather than a bare state word on a button ("Open") or a description bolted on beside it.
- No settings on consumer screens. Configuration lives on the feature's Setup or Edit page, with defaults that suit most groups, and rarely used choices behind a "More choices" disclosure.
- Every new setting, button or option has to earn its place: first ask whether a good default would do, and whether an existing option can absorb it. Removing an option is a good change.
- Keep the flexibility admins rely on; just keep it out of everyone else's way.

### The standard, by screen kind

Reasoning, sketches, the screen kit and upstream's exceptions: `fork/specs/screen-standard-spec.md`. Words and button styles: gp-map "Views". Use the screen kit partials (`shared/_page_header`, `_state_line`, `_action_row`, `_inline_confirm`, `_filter_bar`, `_people_table`, `_empty_state`, `_record_tabs`) and `screen_action`; never a near-copy of their markup.

- **Layers.** 1 list, 2 record, 3 edit/new, 4 feature setup (its types, lists and settings, reached from the main Setup page), 5 site settings. Every layer has a breadcrumb; it's the one way back (no Back buttons on records; forms have Cancel).
- **Page shape.** Header card: `h1` title, one-line summary, the state in words (record pages). Then filters, then the content, then the action row in the card footer.
- **Lists (1).** Upstream's filter card: fields, then New <thing>, Search, Clear Search in its footer. Results below in `table-responsive`, with an empty-state line ("Nothing here yet.", "Nobody here.").
- **Records (2).** Footer action row: Edit first, then the page's one job action (Remind, Sign up, Approve), then **More** for everything else. Delete is the last More item; with no More menu (three actions or fewer) it's the last button. Actions on a table (Print, Download CSV) sit at the right of its filter bar. More than two parts: link tabs under the header (`people/_show_shared`).
- **Edit pages (3).** Fields, then Cancel, Save (Save last; pinned per BL-055). A setup with more than two parts uses link tabs, one save per tab (`forms/edit`), not a stack of sections. Rare choices behind "More choices".
- **Feature setup (4).** A vocabulary is a list page ("Defined things" below); feature-wide settings are an edit page. Never on a reading screen.
- **State** (open/closed, published, counting) is a labelled radio choice on the Edit page that says its effect, and the record page shows it in words with a link to the choice. Never a state button, never a bare status select. **Archive and Restore** are lifecycle actions, not states: never in that choice; the last items in More before Delete, each with a confirm naming the effect, on their own routes (never `DELETE`). **Decisions** on someone's request (Approve, Decline, Ask for changes) are buttons on the record for the person whose turn it is.
- **Confirming.** Saving a form asks inline (below). One-click buttons with no form (Delete, Archive, Restore, Remove, Withdraw, Cancel request) use `turbo_confirm`, worded with the effect ("Delete this event and its 12 check-ins?"), never "Are you sure?".
- **Other kinds.** Print view: controls at the top, hidden when printing. One-step action page: the thing, the question, Cancel and a button named for the effect. My GatherPack row: one solid action, the rest outline. Public page: one card, one primary button.
- **Phone.** The action row keeps its first action and More (the rest move into More); tables scroll sideways; filters fold behind a Search/Filters button.

- **Copy:** directions say what to do, in order, in one or two plain sentences, with a concrete example when the use isn't obvious. No abstract taglines ("little wisps of AI garbage") or insider terms ("basis", "intent", "on file"). Label fields by the question they answer ("Who to include", "Columns"). Button words shouldn't sound permanent when the action is safe ("Take Snapshot", not "Record this list").
- **Name features for what they do in general**, not after the first use case.
- **Start from the thing the page is about**, then plain radio choices with their settings inline; progressive pickers that reveal without a reload; tick boxes over multi-selects; one general option over several special cases.
- **Warnings sit by the action:** a short question just above Save with inline choices (safe default selected), applied by the save (`shared/_inline_confirm`). No page-top alerts with immediate-action buttons.
- **Several choices mean "any of".** When a screen lets someone add more than one team, badge or rule of a kind, the model must treat them the way the screen reads (normally any-of), or the screen must block a second one. Say it on screen ("Any of these teams").
- **Signed up is not done.** Planned or signed-up records go under their own **Upcoming** heading (soonest first), apart from **Done** (confirmed only, newest first); "Still open" is a third list.
- **Status words** default to Complete / In Progress / Not Started, and can be overridden per checklist and per item. Don't argue finer distinctions against plain words the owner picks.
- **Guardian parts only when a guardian is reached:** split counts and wording into "themselves" and "guardians" only when the real recipients include guardians. Steer guardians with wording, not new permission settings.
- **Native over config:** surface a feature the way the nearest existing feature does (native card, profile tab), even if that costs a one-line `render` in an upstream view (recorded in `FORK.md`). Never a second mechanism such as an admin-built widget.
- **Match upstream's look:** copy the nearest upstream screen. Buttons follow gp-map "Views".
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
