# BL-026: Placing someone as an organizer looks like signing up yourself

| | |
|---|---|
| Kind | upstream feature |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-29 |
| Upstream commit checked | `3fa5700` (`upstream/main`); code is on `feature/signups` `8f79447` and `feature/signups-widget` `8432bc6` |
| Planned branch | `feature/signups` (lists and wording); `feature/signups-widget` picks the change up for the dashboard card |
| Upstream issue / PR | none |

## Summary

An admin added three students to an event's volunteer slot. Each sign-up was correct (the student was the person taking the place and the one it was on behalf of), but `signed_up_by` was the admin. Because of that, all three showed up in the admin's own "My sign-ups" list and on their dashboard's "My Sign-ups and Commitments" card, the same way a place the admin took themselves would. The only sign they were someone else's was a small grey "For <name>" line. The admin assumed they had signed themselves up three times and cancelled all three, which cancelled the students' places. We fixed it by hand: we set the three sign-ups back to active and changed `signed_up_by` to each student.

The data model is fine: `person`, `signed_up_by` and `on_behalf_of` already separate who takes the place, who made the sign-up, and who it's for. The problem is how organizer placements are shown to the organizer afterwards.

## Evidence

- Both ways of adding someone record the current user as the signer: the roster's add (`RosterSignupsController#create`, `app/controllers/roster_signups_controller.rb:52`) and the member dialog (`SignupsController#create`, `app/controllers/signups_controller.rb:35`, with `signer` at `:88`). We don't know which one the admin used. They added the three students within 25 seconds and cancelled all three about 17 minutes later.
- The viewer's personal lists include every sign-up they made for anyone: `SignupSheetsController#signups_involving` (`app/controllers/signup_sheets_controller.rb:118`) and `SignupsSummary#all_signups` (`app/models/signups_summary.rb:79` on `feature/signups-widget`).
- `app/views/signup_sheets/_member_signups.html.erb`: the heading is "My sign-ups" (`:3`). Someone else's place is marked only by the small "For <name>" line (`:21`). The Cancel confirmation reads "Cancel this sign-up?" (`:34`) and doesn't say whose place gets cancelled. Admins see Cancel on all of them.
- Production on 2026-10-29: 18 sign-ups were made by someone other than the person taking the place (7 active, 11 fulfilled). None were made by an admin account apart from the three fixed above. Guardians signing up their own children are the expected case and should keep showing up in the guardian's list.

## Fix in mind

1. **Keep organizer placements out of the organizer's own lists.** Sign-ups the viewer only *placed from the roster* don't belong in "My sign-ups" or on the dashboard card. Sign-ups a guardian makes for their own child (`SignupSheet#takers_for`) should stay. To tell the two apart, either record where the sign-up came from (a new reversible column such as `signups.placed_by_organizer`, set in `RosterSignupsController#create`), or work it out by checking whether the signer could have picked that taker on the member dialog. Recording it is simpler and still accurate if relationships change later.
2. **Split the list so it's clear whose place each one is.** On the sheet, use "Your places" and "Places you signed others up for" (the second with the taker's name as the main line, not a grey sub-line). The dashboard card gets the same split.
3. **Say whose place is being cancelled.** Change the confirmation to "Cancel Lance's place in Volunteer, Trick or Treat? They'll be told." whenever the taker isn't the viewer. Use the same wording in the roster's cancel.
4. **Optional:** after an admin adds someone, the flash could add "It's on their dashboard, not yours," the first time or every time.

Per rule 10, the list change in step 1 changes behaviour. It can sit behind the existing `feature_signups` flag, since the feature is still wip and the old behaviour is the bug, but confirm with Corey.

## Testing

- Organizer adds a student from the roster: the sign-up is on the student's dashboard card and sheet list and not the organizer's. The roster still shows it with "Signed up by <organizer>".
- Guardian signs up their child from the member dialog: the sign-up stays in the guardian's list under "Places you signed others up for".
- Cancel confirmation names the taker when the taker isn't the viewer. Add system tests next to the existing sign-ups system tests (these need `feature/test-hosts` merged; see FORK.md).

## Strategy fit

Upstream-intended, like the rest of `feature/signups`. It's a change to that branch plus a fork migration if we record the source, with no upstream files beyond what `feature/signups` already touches. `feature/signups-widget` gets it through its dependency chain. In the meantime, `prod-ops` already tells scripts to use the student as `signed_up_by`.
