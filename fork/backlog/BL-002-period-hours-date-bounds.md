# BL-002: Period hours skip meetings near the period's last day

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | waiting |
| Added | 2026-10-03 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/period-hours-date-bounds` |
| Upstream issue / PR | none yet |

## Summary

`TimeClockPeriod#available_hours` and `#total_hours` only count linked events that fall inside the period's dates, but the check compares event *timestamps* against the period's *dates* directly. Postgres treats each date as midnight UTC. As a result:

- An event on the period's **last day** is never counted: `end_time BETWEEN '2026-07-01' AND '2026-12-31'` means "ends by 2026-12-31 00:00 UTC".
- In US time zones, an **evening event on the second-to-last day** is dropped too. A meeting ending 21:00 EST on Dec 30 ends at 02:00 UTC on Dec 31, which is past the bound.
- At the other end, an evening event on the day *before* the period starts can be counted, since 21:00 EDT on June 30 is 01:00 UTC on July 1.

These two numbers are the denominator for "That's X% of the N hours that have accumulated so far" on a person's statistics page, and for the totals on the period page. So attendance percentages are slightly off for any period that has meetings near its boundaries.

## How we found it

HBR uses period hours as the denominator for travel eligibility (attendance as a percentage of meeting hours). While setting that up on 2026-10-03, we noticed the query compares dates to timestamps. In production (time zone setting `America/Indiana/Indianapolis`), we created a meeting on 2026-12-31 18:00–21:00 linked to a Jul 1 – Dec 31 period inside a rolled-back transaction. `total_hours` stayed at 0.

## The code (upstream `32e8023`)

`app/models/time_clock_period.rb`, lines 30–36:

```ruby
def available_hours
  self.events.where(start_time: start_time..end_time, end_time: start_time..end_time).where("end_time < ?", Time.now).map(&:hours).sum
end

def total_hours
  self.events.where(start_time: start_time..end_time, end_time: start_time..end_time).map(&:hours).sum
end
```

`start_time` and `end_time` on `time_clock_periods` are `date` columns. On `events` they are `datetime`. The generated SQL is:

```sql
... AND "events"."start_time" BETWEEN '2026-07-01' AND '2026-12-31'
    AND "events"."end_time"   BETWEEN '2026-07-01' AND '2026-12-31'
```

Punches already handle this correctly. `TimeClockPunch#valid_times` (`app/models/time_clock_punch.rb`) compares against `time_clock_period.start_time.beginning_of_day` and `time_clock_period.end_time.end_of_day`, which are computed in `Time.zone`. `ApplicationController#set_time_zone` sets that zone from `Settings[:time_zone]` for each request.

## Reproduce

1. Set the time zone setting to a US zone, e.g. `America/New_York`.
2. Create a time clock period from Jan 1 to Jan 31.
3. Create an event linked to it on Jan 31, 18:00–21:00.
4. Open the period. "Potential assigned hours" doesn't include the event. `period.total_hours` is 0 in a console run under `Time.use_zone("America/New_York")`.

## Proposed fix

Use the same day boundaries as punches, and extract a shared scope so the two methods can't drift apart:

```ruby
def events_in_period
  range = start_time.beginning_of_day..end_time.end_of_day
  events.where(start_time: range, end_time: range)
end

def available_hours
  events_in_period.where("end_time < ?", Time.current).map(&:hours).sum
end

def total_hours
  events_in_period.map(&:hours).sum
end
```

`Date#beginning_of_day` / `#end_of_day` return `ActiveSupport::TimeWithZone` in `Time.zone`. That is the configured zone in requests, and UTC in jobs and console unless wrapped in `Time.use_zone`, which is the same behavior punches have today.

## Tests

In `test/models/time_clock_period_test.rb`, wrapped in `Time.use_zone("America/New_York")`:

- An event on the period's last day, 18:00–21:00, counts toward `total_hours`.
- An evening event on the second-to-last day counts.
- An evening event on the day before the period starts doesn't count.
- `available_hours` still excludes events that haven't ended (use `travel_to`).

Check upstream's existing fixtures for periods and events before adding new ones.

## Fork strategy notes

- This is a small, self-contained upstream bug fix: one model file and one test file. Send it upstream as is. It needs no flag and no HBR naming.
- Until it lands, HBR is only affected by meetings on Dec 30–31 and Jun 29–30 (the last days of our two periods). Our attendance report page (`~/dev/gatherpack/pages/attendance-report.html.erb`) doesn't use these methods: it counts every ended event linked to the period, without the date filter.

## Related, not part of this fix

The statistics page divides *all* punched hours by `available_hours`, so time punched outside meetings (staying late, extra build days) can push attendance over 100%. HBR's report credits only the time a punch overlaps a meeting. Whether upstream wants that is a separate feature conversation, not a bug.

## Draft upstream issue

> **Period hours skip events on the period's last day**
>
> `TimeClockPeriod#available_hours` and `#total_hours` filter events with `start_time: start_time..end_time`, comparing event timestamps against the period's date columns. Postgres reads the dates as midnight UTC, so an event on the period's last day is never counted, and in US time zones an evening event on the second-to-last day is dropped too. Punch validation already uses `beginning_of_day`/`end_of_day` for these bounds. Happy to send a PR that does the same here, with tests.
