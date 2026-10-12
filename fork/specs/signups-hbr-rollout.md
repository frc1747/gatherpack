# HBR rollout: Sign-up Sheets and Commitments

Status: draft, 2026-10-11. Configuration and migration for HBR. The framework is [`signups-spec.md`](signups-spec.md); nothing here should require a change to it. If it does, change the framework spec first (its §1.1).

Split from signups-spec rev. 4. Its HBR decisions are below, renumbered.

## 1. Goal

Replace the team's SignUpGenius sheets with GatherPack sign-ups tied to Events, and track whether students' families have done the shifts and outreach they owe.

- **Purdue Football Concessions.** Seven games. Each game has the same five positions with their own caps: Shift Lead (1), Cook (2), Cashier, alcohol license required (4), Stockers 18+ (4), Students 16/17 (6 or 2, varies by game). Some sign-ups fill two places (a couple). Some shifts are worked for another family ("working for [another student]"). Each family owes 2 shifts, plus 1 for each additional student. Two games have "time TBA".
- **Stocking.** Seven Wednesday sessions. Student Stocker (3) and Adults (2). Three student stocking sessions count as one concessions shift, with no limit: six sessions cover a family's two shifts. Adult slots count toward nothing; they exist because each session needs two adults supervising.
- **Outreach.** Students owe a number of outreach events. Student leaders run it. Some outreach has a sign-up (a camp, a fair booth); much doesn't (mentoring, walk-ins) and is recorded only as check-ins on Outreach events.

- **Saturday lunches** (next after concessions). Parents sign up to bring food and supplies, and to work the lunch serving students.

## 2. Each rule as configuration

| HBR rule | Configured as |
|---|---|
| Cashier needs an alcohol license | Badge rule: "Alcohol License" |
| Cooks and stockers are adults; Students 16/17 | Team rule: any of Parents or Friends of HBR; age rule min 16, max 17 plus team Students. Stocking "Adults" keeps age min 18 |
| A couple fills 2 cashier places | Two sign-ups, one each; they count as 2 shifts toward the family's requirement (Corey, 2026-10-11) |
| "Working for [another student]" | Sign-up on behalf of that student |
| Concession shift = 1 | Sign-up sources: Concessions sheet and the commencement sheet, 1 per 1; check-ins at Concessions events, 1 per 1 |
| 3 stocking = 1 shift | Sign-up source: Stocking → Student Stocker, 1 per 3, no cap; check-ins at Concessions Stocking events, 1 per 3 |
| Adult stocking counts for nothing | Adults position isn't a source |
| 2 for the first student, +1 per additional | Grouped by Parent/Guardian – Student; base 2, additional 1 |
| Outreach events, with or without a sign-up | Per-person commitment; check-in source on event type Outreach |
| Parents run concessions, student leaders run outreach | Two organizer grants with different highest teams |
| "Concessions done" on the Eligibility Report | The report reads each commitment's progress (spec decision 17) |
| Rookies don't owe outreach | Exempt badge: "2027 Season Rookie" (next season's badge each year) |

## 3. Production today (checked 2026-10-11)

- Teams: FIRST Team 1747 (top, 7 members, all managers) → Mentors, Team 1747 - Parents (73), Student Leadership, Team 1747 - Students → Class of 2027–2030 (50 students).
- One relationship type, Parent/Guardian – Student (78 links; all 73 parents in it are on the Parents team). "Parent Board" means every parent; the Board of Directors isn't a team.
- `forms_creator_badge` is "Student Form Creator", capped at Students, held by the 7 members of Student Leadership.
- 1 of 50 students has a birthday on file.
- Event types Concessions (9 events) and Concessions Stocking (7), all on "Team 1747 - Students", at noon with no end time. Their check-ins (1–10 each, students only, including events in November) were created in bulk on 2026-10-04 from SignUpGenius and mean "shift credited", not "showed up". Concessions has two check-in fields, Shifts (1–3) and Worked by (free text).
- Event type Outreach: 38 events on "Team 1747 - Students", most at noon with no end time (22 are single camp days). Their check-ins (students only) were imported on 2026-10-04 from roster sheets (notes like "Roster sheet: Fair").

## 4. Configuration

**Organizers.** Admins give an admin-assigned badge "Sign-up Organizer" to specific parents (the concessions coordinators, and any director who runs a sheet). `signups_organizers` and `commitments_organizers` both pair it with "FIRST Team 1747, Harrison Boiler Robotics", so a coordinator on the Parents team can own a sheet at the top team and open it to Students and Parents. Both also pair "Student Form Creator" (or a new student-leader badge) with "Team 1747 - Students", so student leaders run outreach without reaching parents.

Ditto is the reference for everything below (Corey, 2026-10-12): production is made to match it.

**Concessions sheet** ("Purdue Football Concessions"). Team: top. Audience: Students, Parents and Friends of HBR (team "Team 1747 - Friends of HBR"). Positions Shift Lead (1, no rules), Cook (2, team any of Parents or Friends of HBR), Cashier (4, badge Alcohol License), Stocker (4, team any of Parents or Friends of HBR), Student (6, team Students, age 16–17; cap 2 on some games). Reminders 2 days before; no cancel cutoff. The 7 game events; the two without a kickoff time are 00:00–23:59 until it's announced. Sign up others via Parent/Guardian – Student; on behalf of: anyone. Shift Lead pairing per framework decision 6.

**Stocking sheet** ("Concessions Stocking"). Same team and audience. Positions Student Stocker (3, team Students), Adults (2, min age 18); 7 events; same relationship settings.

**Commencement sheet** ("Purdue Global Commencement Concessions", closed). The 10/3 Purdue Global commencement at Mackey Arena (pretzel carts), 8:00 am–7:00 pm. One position, Cart (no cap, no rules), holding the four people who worked it; same team and audience.

**Commitment "Concessions 2026".** Owed by Students, grouped by Parent/Guardian – Student, base 2, additional 1, unit "shifts", counts when confirmed. Sources in order: Concessions sheet (all positions, 1 per 1), commencement sheet (1 per 1), Stocking → Student Stocker (1 per 3, no cap), check-ins at Concessions events (1 per 1), check-ins at Concessions Stocking events (1 per 3). The check-in sources credit students who work without signing up; dedupe per worker and event keeps a fulfilled sign-up from counting twice. Period: season start (2026-05-01) to the day before kickoff (2027-01-08). The Eligibility Report's concessions column reads this commitment's progress for the student's family.

**Commitment "Outreach 2026–27".** Owed by Students except holders of "2027 Season Rookie", per person, base = the report's `outreach_required` (1 today), period May 1–Apr 30, unit "events", counts when confirmed. Team: "Team 1747 - Students". Sources: check-ins at Outreach events (1 per 1); an outreach sheet the student leaders post can be added ahead of it. The Eligibility Report's outreach column reads its progress. On Ditto since 2026-10-11 (`~/dev/gatherpack-import/ditto_outreach_commitment.rb`). The 22 camp days are separate events, so a week-long camp counts as five; if it should count once, that's a ratio or cap on that camp's sheet source.

**Saturday lunches (next).** One sheet, team and audience like the concessions sheet, one event per Saturday. Item positions for what's needed (for example Main dish, a quantity in servings or pans, with the question "What are you bringing?"; Drinks; Paper goods) and a people position for servers. Settled 2026-10-12:

- Lunches don't count toward any commitment. No source points at the lunch sheet.
- Nothing to migrate; the sheet starts empty.
- The items, quantities and number of servers aren't fixed in advance. The lunch organizers set them on the sheet when they start using it, and can change them per Saturday.

## 5. Migration

A one-off script in `~/dev/gatherpack-import`, like the enrollment import; not part of any branch. One transaction with before/after counts, after confirming with the fork owner.

1. Create both sheets and attach the existing 16 events. Set real start and end times (all noon with no end today); 11/7 and 11/21 get 00:00–23:59 until kickoff is announced.
2. Import the SignUpGenius sign-ups (CSV export): one sign-up per person who works, and on behalf of parsed from notes ("working for [student]"), matching names to people by hand where needed.
3. Turn each 2026-10-04 Concessions and Stocking check-in (meaning "credited to this student") into a sign-up on behalf of that student, unless step 2 covers it. Use the Concessions check-in fields: **Shifts** (places filled) and **Worked by** (who worked, when not the student): one sign-up per worker. Where Shifts is more than the known workers, ask the coordinators who the others were. Delete the check-ins on events that haven't happened. Keep check-ins on past events; they mark those sign-ups fulfilled (decision 4).
4. Outreach check-ins stay as they are; the check-in source counts them.
5. Corrections found by comparing the reports (2026-10-11): Sushanth Ankammagari did not work 9/4 although SignUpGenius lists him (mark that sign-up no-show). Kamden and Karsen Williams worked 9/4 without signing up; keep their check-ins, which credit them. Four Class of 2030 students (Eric Hudson, Pru Madsen, Yavor Piperov, Timothy Woolwine) lack the "2027 Season Rookie" badge that excuses outreach; the old report treated them as rookies by class.
6. Concessions 9/8 and 10/3 aren't on the SignUpGenius sheet (answered 2026-10-11). "9/8" was a typo for the 9/2 stocking session: credit those check-ins on "Concessions Stocking 9/2" and delete the 9/8 event. 10/3 was a real concessions event (a commencement, pretzel carts): it gets its own closed sheet with one "Cart" position and no rules, holding the people who worked it.

## 6. Decisions

Settled 2026-10-11 (numbers from signups-spec rev. 4 in brackets).

1. **Organizers are parent coordinators and student leaders** [8]. No Parent Board or Board of Directors team; the team tree is unchanged. Don't make anyone a manager of the Parents team for this.
2. **Separate settings from forms** [9]. HBR's form creator badge belongs to students; it's listed again as an outreach organizer grant.
3. **Student leaders see every student's outreach totals** [14], and nothing else from their records.
4. **Credit check-ins are converted** [11]. Today's concessions check-ins mean "credited"; the migration turns them into sign-ups so check-ins mean "showed up" from now on.
5. **Build age rules even though birthdays are missing** [12]. Collecting them is HBR's job (for example a form that updates profiles). Until a birthday is known, organizers place that person.
6. **Outreach counts events** [13], not hours.
