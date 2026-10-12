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
| Stockers 18+, Students 16/17 | Age rules: min 18; min 16, max 17 |
| A couple fills 2 cashier places | Two sign-ups, one each; they count as 2 shifts toward the family's requirement (Corey, 2026-10-11) |
| "Working for [another student]" | Sign-up on behalf of that student |
| Concession shift = 1 | Sign-up source: Concessions sheet, 1 per 1 |
| 3 stocking = 1 shift | Sign-up source: Stocking → Student Stocker, 1 per 3, no cap |
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

**Concessions sheet.** Team: top. Audience: Students and Parents. Positions Shift Lead (1), Cook (2), Cashier (4, badge Alcohol License), Stocker (4, min age 18), Student (6, team Students, age 16–17; cap 2 on some games). The 7 game events; the two without a kickoff time are 00:00–23:59 until it's announced. Sign up others via Parent/Guardian – Student; on behalf of: anyone. Shift Lead pairing per framework decision 6.

**Stocking sheet.** Positions Student Stocker (3, team Students), Adults (2, min age 18); 7 events; same relationship settings.

**Commitment "Concessions 2026".** Owed by Students, grouped by Parent/Guardian – Student, base 2, additional 1, unit "shifts", counts when confirmed. Sources in order: Concessions sheet (all positions, 1 per 1), Stocking → Student Stocker (1 per 3, no cap). Period: season start (May 1) to kickoff (2027-01-09). The Eligibility Report's concessions column reads this commitment's progress for the student's family.

**Commitment "Outreach 2026–27".** Owed by Students except holders of "2027 Season Rookie", per person, base = the report's `outreach_required` (1 today), period May 1–Apr 30, unit "events", counts when confirmed. Sources in order: any outreach sheet the student leaders post, then check-ins at Outreach events (1 per 1). The Eligibility Report's outreach column reads its progress. On Ditto since 2026-10-11 (`~/dev/gatherpack-import/ditto_outreach_commitment.rb`). The 22 camp days are separate events, so a week-long camp counts as five; if it should count once, that's a ratio or cap on that camp's sheet source.

**Saturday lunches (next).** One sheet, team and audience like the concessions sheet, one event per Saturday. Item positions for what's needed (for example Main dish, a quantity in servings or pans, with the question "What are you bringing?"; Drinks; Paper goods) and a people position for servers. Not decided yet, and to ask the lunch coordinators before configuring:

- The item list, units and quantities per Saturday, and whether they vary by date.
- How many servers each lunch needs, and whether students can serve.
- Whether lunches count toward any commitment (a new one, or the concessions one), and if so whether bringing food counts, serving counts, or both.
- Whether there's anything to migrate (an existing SignUpGenius sheet or spreadsheet).

## 5. Migration

A one-off script in `~/dev/gatherpack-import`, like the enrollment import; not part of any branch. One transaction with before/after counts, after confirming with the fork owner.

1. Create both sheets and attach the existing 16 events. Set real start and end times (all noon with no end today); 11/7 and 11/21 get 00:00–23:59 until kickoff is announced.
2. Import the SignUpGenius sign-ups (CSV export): one sign-up per person who works, and on behalf of parsed from notes ("working for [student]"), matching names to people by hand where needed.
3. Turn each 2026-10-04 Concessions and Stocking check-in (meaning "credited to this student") into a sign-up on behalf of that student, unless step 2 covers it. Use the Concessions check-in fields: **Shifts** (places filled) and **Worked by** (who worked, when not the student): one sign-up per worker. Where Shifts is more than the known workers, ask the coordinators who the others were. Delete the check-ins on events that haven't happened. Keep check-ins on past events; they mark those sign-ups fulfilled (decision 4).
4. Outreach check-ins stay as they are; the check-in source counts them.
5. Corrections found by comparing the reports (2026-10-11): Sushanth Ankammagari did not work 9/4 although SignUpGenius lists him (mark that sign-up no-show). Kamden and Karsen Williams worked 9/4 without signing up; keep their check-ins, which credit them. Four Class of 2030 students (Eric Hudson, Pru Madsen, Yavor Piperov, Timothy Woolwine) lack the "2027 Season Rookie" badge that excuses outreach; the old report treated them as rookies by class.
6. Concessions 9/8 and 10/3 aren't on the SignUpGenius sheet. Ask the coordinators what they were before importing their check-ins.

## 6. Decisions

Settled 2026-10-11 (numbers from signups-spec rev. 4 in brackets).

1. **Organizers are parent coordinators and student leaders** [8]. No Parent Board or Board of Directors team; the team tree is unchanged. Don't make anyone a manager of the Parents team for this.
2. **Separate settings from forms** [9]. HBR's form creator badge belongs to students; it's listed again as an outreach organizer grant.
3. **Student leaders see every student's outreach totals** [14], and nothing else from their records.
4. **Credit check-ins are converted** [11]. Today's concessions check-ins mean "credited"; the migration turns them into sign-ups so check-ins mean "showed up" from now on.
5. **Build age rules even though birthdays are missing** [12]. Collecting them is HBR's job (for example a form that updates profiles). Until a birthday is known, organizers place that person.
6. **Outreach counts events** [13], not hours.
