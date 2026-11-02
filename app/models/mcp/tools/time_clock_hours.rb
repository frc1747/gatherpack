# Hours on the time clock per person, as the time clock summary page adds
# them up (TimeClockPeriodsController#summary). The page's gate is
# policy_scope(TimeClockPeriod): TimeClockPeriodPolicy#summary? forwards to the
# default show? and protects nothing. So punches are those in a period in
# policy_scope(TimeClockPeriod), through TimeClockPunchPolicy::Scope (admins
# all, managers their managed teams' people and themselves, everyone else
# their own). Punches outside any period are left out, as the summary leaves
# them out. A person must be in policy_scope(Person) as well; for person_id the
# person must also pass PersonPolicy#show?, for team_id the team must be in
# policy_scope(Team) and people are the members of the team and its sub-teams.
# Punches count by their start time, from and to inclusive, at most 366 days.
# Each punch's hours are the page's own (punch.hours, rounded to 0.05 as the
# page rounds them). An open punch counts up to now or the end of `to`,
# whichever is earlier, and sets open_in_window; that is about this window
# only, clocked_in_now is the live answer. An open punch that hasn't started
# yet (a start time in the future) is left out entirely. Hours come from every
# period the viewer can see, not only the filtered team's.
class Mcp::Tools::TimeClockHours < Mcp::Tool
  MAX_WINDOW_DAYS = 366

  tool_name "time_clock_hours"
  description "Hours on the time clock between `from` and `to` (YYYY-MM-DD, inclusive, at most 366 days apart) for one " \
    "person or the members of one team, per person, counting punches in all time clock periods you can see, " \
    "not only that team's. An open punch that started in the window is counted up to now or the end of `to`, " \
    "whichever is earlier, and sets open_in_window: that says something about this window only; " \
    "use clocked_in_now to see who is clocked in at the moment."
  scope :read
  feature :time_tracking
  input_schema(
    properties: {
      person_id: { type: "string", description: "One person (per_ ID); give this or team_id" },
      team_id: { type: "string", description: "A team and its sub-teams (tm_ ID); give this or person_id" },
      from: { type: "string", description: "First day, YYYY-MM-DD" },
      to: { type: "string", description: "Last day, YYYY-MM-DD" },
      limit: limit_property
    },
    required: %w[from to]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            person: REF_SCHEMA,
            hours: { type: "number" },
            open_hours: { type: "number" },
            open_in_window: { type: "boolean" },
            punches: { type: "integer" }
          },
          required: %w[person hours open_hours open_in_window punches]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(from:, to:, person_id: nil, team_id: nil, limit: DEFAULT_LIMIT)
    invalid_argument!("Give person_id or team_id") if person_id.nil? && team_id.nil?
    invalid_argument!("Give person_id or team_id, not both") if person_id && team_id

    window = date_window(from, to)
    people = ctx.policy_scope(Person)
    if person_id
      person = ctx.find(Person, person_id)
      ctx.authorize!(person, :show?)
      people = people.where(id: person.id)
    else
      people = people.where(id: ctx.find(ctx.policy_scope(Team), team_id).descendant_member_ids)
    end

    punches = ctx.policy_scope(TimeClockPunch)
      .where(time_clock_period_id: ctx.policy_scope(TimeClockPeriod).select(:id), start_time: window)
      .where("time_clock_punches.end_time IS NOT NULL OR time_clock_punches.start_time <= ?", Time.current)
    people = people.where(id: punches.select(:person_id))

    result = list(people.order(:last_name, :first_name, :id), limit: limit) { |record| record }
    by_person = punches.where(person_id: result[:items].map(&:id)).group_by(&:person_id)

    result.merge(items: result[:items].map { |record| hours_json_for(record, by_person.fetch(record.id, []), window.end) })
  end

  private

  def hours_json_for(person, punches, window_end)
    open, closed = punches.partition { |punch| punch.end_time.nil? }
    closed_hours = closed.sum(&:hours)
    counted_until = [ Time.current, window_end ].min
    open_hours = open.sum { |punch| ((counted_until - punch.start_time) / 3600 * 20).round / 20.0 }
    {
      person: person_json(person),
      hours: hours_json(closed_hours + open_hours),
      open_hours: hours_json(open_hours),
      open_in_window: open.any?,
      punches: punches.size
    }
  end

  # from.beginning_of_day..to.end_of_day in the app's time zone.
  def date_window(from, to)
    first = parse_date(from, "from")
    last = parse_date(to, "to")
    invalid_argument!("to can't be before from") if last < first
    invalid_argument!("The window can be at most #{MAX_WINDOW_DAYS} days") if (last - first).to_i >= MAX_WINDOW_DAYS

    first.in_time_zone.beginning_of_day..last.in_time_zone.end_of_day
  end

  def parse_date(value, name)
    raise Date::Error unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    invalid_argument!("#{name} must be a date like 2026-03-31")
  end
end
