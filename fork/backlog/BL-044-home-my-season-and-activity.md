# BL-044: Home shows checklist math instead of answers; add a "My activity" page

| | |
|---|---|
| Kind | fork-only (UX) |
| Priority | high (top of the queue, Corey 2026-11-15) |
| Status | shipped hbr.41 |
| Added | 2026-11-15 |
| Commit checked | `hbr/integration` @ `2d28c89f` (`v0.0.0-hbr.40`); `feature/my-gatherpack-checklists` @ `9d1e264c` |
| Planned branches | `feature/my-gatherpack-checklists` (Home wording and grouping), new `feature/my-gatherpack-activity` (activity page) |
| Upstream issue / PR | none |
| Mock-up | [Home card mock-up](https://claude.ai/artifact/4uzkEM4KVvamz6fwF7JYhg) (private to Corey; two screens: the card for four people, and "See all your activity") |

## Summary

Home's **Your Checklists** shows each measuring item as `confirmed of owed` with a bar (spec [`my-gatherpack-spec.md`](../specs/my-gatherpack-spec.md) §6.2). That's correct but reads as the formula, not the answer: a met attendance item shows "8.1 h of 8.1 h", where 8.1 h is the share of hours held so far, not the hours the person has. Most members and parents won't follow it.

Corey also wants people to see their own activity (outreach, hours, sign-ups) even where no checklist asks for it. A rookie, for example, isn't on the Outreach checklist but takes part in Outreach. A second "stats" section next to the checklists would show the same facts twice in different words. So the decision is **one card on Home that answers "am I OK?"**, and **a separate activity page that answers "what have I done?"**.

## Where things are (`9d1e264c`)

- `app/helpers/my_gatherpack_checklists_helper.rb:51-59`: the `"#{confirmed} of #{owed}"` text (plus " h"); `:76-79` the bar percentage.
- `app/views/my_gatherpack/_checklists_season.html.erb`: the Your Checklists side section; `_todo_row.html.erb`: checklist to-dos.
- `config/initializers/my-gatherpack-checklists.rb:6-8`: the `:checklists_todo` (`:todo`) and `:checklists_season` (`:side`) sections.
- `config/initializers/my_gatherpack.rb:18-21`: `:events` (`:coming_up`), widgets, announcements.
- `SignupsSummary#shown_as_checklist_item?` (`app/models/signups_summary.rb:118-121` on `hbr/integration`): today's precedent for not showing a commitment twice.

## Design (see the mock-up)

### Home card

1. **Status in words; numbers only when there's a gap.**
   - Met: say so and show what the person did ("Attendance ✓ 44 h this fall"), never the threshold.
   - Not met: the gap and the deadline ("Attendance: 3.5 more hours by Dec 31").
   - The full formula ("8.7 h of the 57 h held so far, you have 5.2 h") moves into the item's tap-through detail.
2. **Groups:** To do (unfinished, each with one specific action), Coming up (sign-ups and events, as today), Done (collapsed to one line, expandable). With nothing to do: "You're all set for now".
3. **Each fact appears once, decided by reference, not by matching numbers:**
   - Checklist items come first. They already carry forms (form items), commitments (count items), sign-ups and check-ins (count sources) and attendance.
   - Forms due that **no** checklist item lists (by form id) stay as to-dos, as today.
   - Coming up is the calendar of places, not requirements. A to-do's "Sign up: Sat Nov 21" links to the sheet.
   - "Also this season" lists the person's own activity (check-ins and hours by event type) only for event types and sheets that none of their checklist count items counts. For a rookie: "Outreach: 2 events · 6 h".
4. **Guardians:** one card, each line tagged with the ward's name; pooled counts read "1 more shift for your family".
5. Footer link: "See all your activity →".

### "My activity" page

The person's own records only, for a season (May 1 – Apr 30, switchable to earlier seasons):

- Totals: meeting hours (and meetings attended of held), events by type, hours at events outside meetings, upcoming sign-ups.
- **By kind of event:** events and hours per event type, plus what each counts toward ("Counts toward Concessions 2026", "Not required for you this season"). Tapping a row filters the history.
- **History:** every check-in, time clock entry, fulfilled sign-up and submitted form, newest first, with how it was recorded and the hours.
- Coming up, and "Your checklists" with each one's status, linking to them.
- A guardian switches between wards at the top. Wards' time clock punches follow `TimeClockPunchPolicy` as on the family page (spec §7.3).

### The leak rule

Neither screen names or links a checklist the viewer isn't on. "Counts toward" names only checklists that cover the person; otherwise it reads "Not required for you".

## Decisions (Corey, 2026-11-15)

Settled in `my-gatherpack-spec.md` rev. 5 (decisions 12–16):

1. Attendance covers meetings; everything else is activity. Meeting hours are never in "Also this season".
2. Forms stay in Home's To do (already the case on Home); a form a checklist lists shows only as that checklist item.
3. On a phone the activity page stacks into one column, and History becomes a list.

Task specs (not committed; `~/dev/gatherpack/tasks/`): 280 Home checklist lines, 281 activity page (new `feature/my-gatherpack-activity`), 282 rule wording (BL-045), 283 demo personas.

## Done when

1. Spec: `my-gatherpack-spec.md` §6.2 revised and a new activity page section added, with the dedupe rules above. Corey approves before code.
2. Built on the planned branches with tests: the met and not-met wording; dedupe (a form on a checklist isn't a separate to-do; an event type counted by a count item isn't in "Also this season"); the leak rule (a person not covered by a checklist never sees its name or a link to it); guardian view; the §6.3 performance budget.
3. Released (`fork-release`) and **deployed to demo.hbrlive.com**. The demo DB is rebuilt from that release (`prod-ops`, Demo database), and its personas include a rookie, a member who's behind, one who's all done and a guardian with two wards, with check-ins of several event types.
4. **GP Help** (`~/dev/gphelp`, its lead session) re-captures every guide that shows Home or checklist progress (tour, on your phone, check your hours, commitments, your student's hours, the family page, read a checklist…). It adds a members guide for the activity page, and the screenshots match the new screens.

## Related

- [BL-045](BL-045-checklist-rule-wording.md): the sign-up position rule's "Finishes a checklist" wording and the catch-22 warning.
- [BL-046](BL-046-wrapped-checklist-exempt-people.md): checklists converted from commitments treat an exempt badge as "not on the checklist".

## Fork strategy notes

Fork-only (My GatherPack is fork-only). Behaviour changes sit behind `feature_my_gatherpack`. The activity page gets its own flag, default off, so it can ship separately.
