# BL-058: Form creators can't pick teams on the audience tab, and can't ask a team outside their own branch

| | |
|---|---|
| Kind | fork-only (bug + small feature) |
| Priority | medium |
| Status | waiting |
| Added | 2026-11-19 |
| Commit checked | `hbr/integration` @ `c4700b175` (hbr.51) |
| Planned branches | `feature/forms` |
| Upstream issue / PR | none |

## Summary

A student with the form creator badge made an event sign-up form that needed to ask the student team **and the mentors**. The form started out asking the student team, which it owns, but she couldn't add the mentors. Two separate problems:

1. **Bug:** on a form's Audience tab, the "Add team" picker lists only the teams the viewer manages (or every team, for admins). A form creator who manages no team gets an empty picker, even for teams the rules already let them ask.
2. **Gap:** a creator may only ask teams in their own branch, at or below `forms_creator_highest_team`. Mentors sits beside Students, not below it, so even with the bug fixed there's no way to let student creators ask the mentors.

## Evidence

- `app/views/forms/_edit_audience.html.erb:46`: `teams = admin ? Team.order(:name) : current_user.person.all_managed_teams.order(:name)`. The badge picker on line 47 does the same thing.
- `app/policies/form_audience_rule_policy.rb` `#targetable?`: a team rule is allowed for `all_managed_teams` **or**, for the form's creator, `Form.creator_team_ids(person)`. So the policy allows what the picker hides.
- `app/policies/form_policy.rb` `#assignable_teams` includes the creator teams, so the "Owning team" picker works. Only the audience picker is wrong.
- `app/models/form.rb` `.creator_team_ids`: the teams a person belongs to, those below them, and the teams above them up to the `forms_creator_highest_team` cap.
- `lib/settings.rb:202`: `forms_creator_highest_team` (one team name).
- On production the creator manages no team; her creator teams are Students and her class team. Mentors sits under the top-level team, beside Students.

## Fix

### 1. Audience team picker (bug)

The picker offers exactly what `FormAudienceRulePolicy#targetable?` allows for a team rule: managed teams, plus `Form.creator_team_ids(person)` when the viewer runs the form as its creator. Put the list in one place, `FormPolicy#audience_teams`, and use it in both the view and the policy, so they can't drift apart again. If the list is empty, show "No teams you can add" in place of the picker instead of an empty select.

### 2. Extra teams form creators may ask (setting)

Add a setting, **"Other teams form creators can ask"**: a list of teams (one team name per line, like `forms_creator_highest_team`), blank by default. A form creator can **ask** these teams on top of their own creator teams, but can't **own** forms for them. They get added to the audience list only, not to `assignable_teams`.

Decisions:
- **Opt-in by the admin, blank by default.** A form's creator reads every answer it collects, so letting a student ask the mentors means students read the mentors' answers. An admin names those teams on purpose.
- **Ask only, not own.** Owning a team's form means managing it for that team. The creator's branch still decides that.
- **Includes the teams below** each named team, the same way `creator_team_ids` treats a creator's own teams.
- The "Include its managers" tick box works as usual for these teams.

For HBR, after release: put Mentors in the new setting (configuration, prod, Corey's call).

## Tests

- Policy: a creator with no managed teams can add a rule for a creator team; can't add one for an unrelated team; can add one for a team named in the new setting (and a team below it) only once it's set; can't make a team from the setting the form's owning team.
- View/system: a creator opening Audience sees their creator teams (and the setting's teams) in the picker; a manager sees their managed teams; an admin sees all; a creator with nothing to add sees "No teams you can add".
- The picker list equals what the policy allows (one shared method).

## Fork notes

Fork-only: forms, creator badges and audience rules all live on `feature/forms`. The setting is new, so no behavior changes until an admin fills it in. No upstream files touched.
