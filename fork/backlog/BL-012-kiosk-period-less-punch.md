# BL-012: Time kiosk crashes for anyone with a punch that has no period

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-08 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/kiosk-period-less-punches` |
| Upstream issue / PR | none yet |

## Summary

When someone scans their card, the time kiosk shows their total hours for each time clock period. If any of that person's punches has no period, the kiosk returns a 500 error instead of their screen, so they can't clock in or out at all.

A punch can have no period on purpose. The manual "New Time Clock Punch" form leaves Time Clock Period optional, and the model and policy treat a period-less punch as a personal, "added by self" entry. The kiosk is the one place that assumes every punch has a period.

We found this in production on 2026-10-08. A mentor's card crashed the kiosk on every scan. They had entered one punch by hand a few days earlier and left the period blank. Data workaround applied: that punch was given the current period. It was the only period-less punch in production. No code changes yet.

## Where things are today (upstream `32e8023`)

- **The crash:** `app/views/time_kiosk/_found_person.html.erb`, line 63: `<%= period.name %>`. Error: `ActionView::Template::Error (undefined method 'name' for nil)`.
- **Where the nil comes from:** `app/controllers/time_kiosk_controller.rb`, lines 12–16 build `@time_clocks` as `{ TimeClockPeriod.find_by_id(punch.time_clock_period_id) => hours }`. A punch with no period produces a `nil` key.
- **The same crash, not seen yet:** `_found_person.html.erb`, line 92 shows `punch.time_clock_period.name` for each open punch. A period-less punch with no end time crashes there too.
- **Period-less punches are intended upstream:**
  - `app/models/time_clock_punch.rb`, line 6: `belongs_to :time_clock_period, optional: true`.
  - `app/models/time_clock_punch.rb`, line 71: `permission_check` returns early when `time_clock_period.nil?`.
  - `app/policies/time_clock_punch_policy.rb`, lines 23–28: the comment reads "punch is not part of any period, i.e. added by self", and the person can edit their own period-less punches.
  - `app/views/time_clock_punches/_form.html.erb`, line 9: the period combobox has no `required`.
- **Other places already handle nil:**
  - `app/controllers/people_controller.rb`, lines 18–22 build the same hash for the person page, and `app/helpers/people_helper.rb`, line 43 (`person_time_clock_as_badge`) checks `if time_clock_period`.
  - `app/helpers/time_clock_punches_helper.rb`, line 3 and `app/views/calendar/calendar.json.jbuilder`, line 48 use `punch&.time_clock_period&.name || ""`.

### Related: "Start Unassigned" does nothing (found 2026-10-09, upstream `86ab397`)

The kiosk's "Start Unassigned" button (`_found_person.html.erb:81`) sends `time_clock_period_id: nil`, and `punch_in` creates a punch only `if @time_kiosk.time_clock_period` (`time_kiosk_controller.rb:33-36`), so it silently goes back to Welcome. If it did create the punch, the person's next scan would hit the crash above. Decide both together: either make the button work (and the view nil-safe), or remove it. The kiosk spec (`fork/specs/kiosk-spec.md` §4.4) leaves it to this item.

## Proposed fix

Kiosk only, matching how the person page and calendar already treat these punches:

1. `_found_person.html.erb` line 63: skip a nil `period` in the totals list, or label it (for example "No period"). Skipping matches the person page, which shows nothing for a nil period. Labeling tells the person the hours exist. Ask upstream which they prefer, or pick labeling, since it hides less.
2. `_found_person.html.erb` line 92: same treatment for open punches (`punch.time_clock_period&.name || "No period"`), so a person with an open period-less punch can still scan in.
3. Optional tidy-up: `TimeClockPeriod.find_by_id(punch.time_clock_period_id)` is an N+1 in both controllers. `includes(:time_clock_period)` and `punch.time_clock_period` would fix that, but keep it out of this PR unless upstream wants it.

## Open question: should the manual form require a period?

That's not part of this fix. Upstream deliberately allows period-less punches, and a blank period also skips the period's permission rules (`permission_check` returns early). For HBR, a punch with no period counts toward no period's hours, so a mentor or student who skips the field loses those hours from reports without noticing. Options:

- Ask Brad whether the form should warn when the period is blank (for example a hint under the field: "Leave blank only for hours that don't count toward a period").
- Or carry a small HBR-only change that makes the field required for non-admins, behind a Settings flag.

Decide after the kiosk fix lands. Meanwhile, a periodic check for `TimeClockPunch.where(time_clock_period_id: nil)` catches these.

## Hooks

No hook changes. The fix is view-only and doesn't create, update or destroy records, so no `CanBeHooked` callbacks or catalog entries are affected.

## Tests

- `TimeKioskControllerTest`: a person whose token finds them, with one punch in a period and one with `time_clock_period: nil`. `find_token` returns 200 and shows the period's total.
- Same, with an open (`end_time: nil`) period-less punch: 200, and the open punch is listed.
- Put these in a new file (for example `test/controllers/time_kiosk_period_less_punch_test.rb`), not the empty `time_kiosk_controller_test.rb` placeholder, which the kiosk spec's Phase 1 fills. Two upstream-bound branches filling the same placeholder would conflict.
- Fixtures: add a period-less punch fixture if none exists (`git grep 'time_clock_period: nil' test` was empty at `32e8023`).

## Fork strategy notes

- Small generic upstream bug, view-only, no migration, no flag. Send it as a direct PR after confirming with Corey. Don't carry it unless upstream declines.
- Until it lands: if anyone's card crashes the kiosk, look for their punches with no period and assign one.

## Draft upstream issue

> **Time kiosk errors for people with a punch that has no period**
>
> `TimeClockPunch` allows `time_clock_period` to be nil (manual "added by self" punches), but the kiosk's found-person screen calls `period.name` on every period in the hours summary (`_found_person.html.erb` line 63) and `punch.time_clock_period.name` on open punches (line 92). If a person has any period-less punch, scanning their token returns a 500 and they can't punch in or out. The person page already skips nil periods in `person_time_clock_as_badge`. I can send a small PR that handles nil in both kiosk spots, with controller tests.
