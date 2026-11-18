# BL-045: "Finishes a checklist" reads as a reward, not a requirement; no warning for a catch-22

| | |
|---|---|
| Kind | fork-only (UX) |
| Priority | high |
| Status | shipped hbr.41 |
| Added | 2026-11-15 |
| Commit checked | `feature/checklists-connectors` (as merged in `hbr/integration` @ `2d28c89f`, `v0.0.0-hbr.40`) |
| Planned branch | `feature/checklists-connectors` |
| Upstream issue / PR | none |

## Summary

A sign-up position can require a checklist (`SignupPositionRule` kind `checklist`, checklists spec §10.3). On the position's rules card the box is titled **"Finishes a checklist"**, which Corey read as "doing this will complete a checklist", the opposite of what it does.

On production an organizer required "Outreach 2026–27: Complete" on every position of an **Outreach** sign-up sheet. Checking in at that event is what completes Outreach, so nobody who hadn't already done outreach could sign up. Rookies, whom the Outreach checklist leaves out, could never pass. A rookie got "Needs Outreach 2026–27: Complete", followed a link to that checklist, and got a 404. Fixed on prod 2026-11-15 by removing the rule (script `remove_outreach_rule_christmas_parade_2026.rb` in `~/dev/gatherpack-import`). No other sheet used a checklist rule.

## Where things are

- `app/views/signup_positions/_rules.html.erb:4`: `kinds["checklist"] = "Finishes a checklist"`.
- `app/views/signup_checklists/_rule_fields.html.erb`: field "Checklist" with hint "Active checklists whose results you can see for everyone. People it doesn't cover can't take the place."; "In Progress is enough" with hint "For when signing up is how people finish it."
- `app/models/checklists/signup_rule.rb:116-123` (`checklist_requirement`): "Needs <title>: <word>", used both as the rule's description and as the failure reason on the sheet (`app/views/signup_sheets/_sheet_slot.html.erb:34`).

## Fix

1. Wording:

   | Now | Proposed |
   |---|---|
   | "Finishes a checklist" | "Needs a finished checklist" (next to "Needs a badge") |
   | "Checklist" | "Checklist they must finish first" |
   | Its hint | "Only people who have already finished this checklist can take this position. People the checklist leaves out can never take it." |
   | "In Progress is enough" / "For when signing up is how people finish it." | "Also allow people partway through" / "Use this when signing up here is how people finish the checklist." |
   | Saved rule "Now: Needs X: Complete" | "Must have finished X first" |

2. Failure reason on the sheet:
   - On the checklist but not done: keep "Needs X: Complete", and link to the checklist only if the person can open it.
   - Not on the checklist: a generic "Not open to you", with no checklist name or link (the leak rule from [BL-044](BL-044-home-my-season-and-activity.md)).
3. Catch-22 warning when the rule is saved (warn, don't refuse). Warn if the position's sheet, or the position itself, is a credit source of a count item in that checklist, or if the sheet's event type feeds a check-in count in it: "Signing up here counts toward X, so requiring it first means only people who already finished can sign up. Turn on 'Also allow people partway through' or drop the rule."

## Tests

Update the text assertions in `test/controllers/checklist_signups_controller_test.rb`. Add tests for the not-covered reason (no name, no link), the covered-but-unfinished link that's shown only when visible, and the warning for both a sheet-credit and an event-type source.

## Fork strategy notes

Fork-only code on `feature/checklists-connectors`. Wording and a warning only, so no new flag. Update checklists spec §10.3 on `hbr/platform`.
