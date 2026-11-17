# Punches in a date window, as TimeClockPunchesController#index lists them (line 7):
# policy_scope(TimeClockPunch), which gives admins all, managers their managed teams'
# people and themselves, everyone else their own; newest first. The person and period
# filters take what the page's own filters offer: policy_scope(Person) and
# policy_scope(TimeClockPeriod) (index.html.erb lines 11 and 24). flagged: true is
# TimeClockPunchesController#flagged (line 20): it needs flagged? and returns the union
# of the page's three groups. The window is on start_time, from and to inclusive, at most
# 366 days. See Mcp::PunchRecords for hours, note and flags.
class Mcp::Tools::ListPunches < Mcp::Tool
  include Mcp::PunchRecords

  MAX_WINDOW_DAYS = 366

  tool_name "list_punches"
  description "Time clock punches you can see, as the Time Clock page lists them, starting between `from` and `to` (YYYY-MM-DD, inclusive, at most 366 days), newest first. " \
    "Admins see all, managers their teams' people and themselves, everyone else their own. flagged: true is the Flag Review page, for admins and managers; anyone else gets \"Not allowed\". " \
    "A note appears only if you can edit the punch; flags are null if you can't open Flag Review."
  scope :read
  feature :time_tracking
  input_schema(
    properties: {
      person_id: { type: "string", description: "Only this person (per_ ID)" },
      period_id: { type: "string", description: "Only this period (tcpd_ ID)" },
      from: { type: "string", description: "First day, YYYY-MM-DD" },
      to: { type: "string", description: "Last day, YYYY-MM-DD" },
      flagged: { type: "boolean", description: "Only punches on the Flag Review page: too long, still clocked in, or overlapping (default false)" },
      limit: limit_property
    },
    required: %w[from to]
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::PunchRecords::SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(from:, to:, person_id: nil, period_id: nil, flagged: false, limit: DEFAULT_LIMIT)
    window = date_window(from, to)
    ctx.authorize!(TimeClockPunch, :flagged?) if flagged

    punches = ctx.policy_scope(TimeClockPunch).where(start_time: window)
    punches = punches.where(person: ctx.find(Person, person_id)) if person_id
    punches = punches.where(time_clock_period: ctx.find(TimeClockPeriod, period_id)) if period_id
    punches = punches.too_long.or(punches.still_clocked_in).or(punches.near_duplicates) if flagged

    result = list(punches.includes(:person, time_clock_period: :team).order(start_time: :desc, end_time: :desc, id: :asc), limit: limit) { |punch| punch }
    result.merge(items: punches_json(result[:items]))
  end

  private

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
