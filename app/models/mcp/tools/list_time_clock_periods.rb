# Time clock periods, as TimeClockPeriodsController#index lists them (line 7):
# policy_scope(TimeClockPeriod), newest first. Active means running right now, the
# kiosk's test for a period to offer (TimeKioskController line 17). open_punches counts
# what the period's page would show the viewer (TimeClockPeriodsController#show, line
# 14): open punches in policy_scope(TimeClockPunch), so a plain member sees only their own.
class Mcp::Tools::ListTimeClockPeriods < Mcp::Tool
  tool_name "list_time_clock_periods"
  description "Time clock periods you can see, as the Time Clock Periods page lists them, newest first: running now by default, or all with active: false. " \
    "open_punches counts only the open punches you can see."
  scope :read
  feature :time_tracking
  input_schema(
    properties: {
      active: { type: "boolean", description: "Only periods running now (default true); false lists all" },
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
            id: { type: "string" },
            name: { type: "string" },
            team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            start_time: { type: "string" },
            end_time: { type: "string" },
            permission: { type: %w[string null] },
            open_punches: { type: "integer" }
          },
          required: %w[id name team start_time end_time permission open_punches]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(active: true, limit: DEFAULT_LIMIT)
    periods = ctx.policy_scope(TimeClockPeriod).includes(:team).order(start_time: :desc, end_time: :desc, name: :asc, id: :asc)
    periods = periods.where("start_time <= :now AND end_time >= :now", now: Time.current) if active

    result = list(periods, limit: limit) { |period| period }
    open_counts = ctx.policy_scope(TimeClockPunch).still_clocked_in.where(time_clock_period_id: result[:items].map(&:id)).group(:time_clock_period_id).count

    result.merge(items: result[:items].map { |period| period_json(period, open_counts.fetch(period.id, 0)) })
  end

  private

  def period_json(period, open_punches)
    {
      id: period.neat_id,
      name: period.name.to_s,
      team: period.team && team_json(period.team),
      start_time: time_json(period.start_time),
      end_time: time_json(period.end_time),
      permission: period.permission,
      open_punches: open_punches
    }
  end
end
