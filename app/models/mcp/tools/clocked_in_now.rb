# People with an open time clock punch, as the flagged punches page lists
# "still clocked in" (TimeClockPunchesController#flagged): the viewer must pass
# TimeClockPunchPolicy#flagged? (admins and managers), and punches come from
# TimeClockPunchPolicy::Scope. On top of the page, people must be in
# policy_scope(Person) and the period is named only if it is in
# policy_scope(TimeClockPeriod), otherwise it is null. The team filter takes a
# team in policy_scope(Team) and matches its members and its sub-teams'
# members. Longest-open first. Narrower than the page: a punch that hasn't
# started yet (a start time in the future) isn't listed.
class Mcp::Tools::ClockedInNow < Mcp::Tool
  tool_name "clocked_in_now"
  description "People who are clocked in right now (an open time clock punch), since when and for how long, " \
    "longest first. For admins and team managers. Optionally only members of one team."
  scope :read
  feature :time_tracking
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only members of this team and its sub-teams (tm_ ID)" },
      limit: limit_property
    }
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
            since: { type: "string" },
            hours_so_far: { type: "number" },
            period: { anyOf: [ REF_SCHEMA, { type: "null" } ] }
          },
          required: %w[person since hours_so_far period]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(team_id: nil, limit: DEFAULT_LIMIT)
    ctx.authorize!(TimeClockPunch, :flagged?)

    punches = ctx.policy_scope(TimeClockPunch).still_clocked_in.where(start_time: ..Time.current).where(person_id: ctx.policy_scope(Person).select(:id))
    punches = punches.where(person_id: ctx.find(ctx.policy_scope(Team), team_id).descendant_member_ids) if team_id
    visible_periods = ctx.policy_scope(TimeClockPeriod).where(id: punches.select(:time_clock_period_id)).index_by(&:id)

    list(punches.includes(:person).order(:start_time, :id), limit: limit) do |punch|
      period = visible_periods[punch.time_clock_period_id]
      {
        person: person_json(punch.person),
        since: time_json(punch.start_time),
        hours_so_far: hours_json(punch.hours_so_far),
        period: period && { id: period.neat_id, name: period.name.to_s }
      }
    end
  end
end
