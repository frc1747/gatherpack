# Events starting in a date window, as the events index finds them
# (EventsController#index: policy_scope(Event)). The team filter takes a team
# in policy_scope(Team). The event type filter looks the type up without a
# policy (EventTypePolicy::Scope returns every row): a type's name is shown on
# every event the viewer can see, so the filter reveals nothing else. Window
# of at most 366 days, from and to inclusive, in the app's time zone. The
# attendee count is the check-in count the event page shows for a visible
# event. Differs from the page only in being narrower for one case: the
# event page itself loads any event by ID, this tool lists only events in
# policy_scope(Event).
class Mcp::Tools::ListEvents < Mcp::Tool
  MAX_WINDOW_DAYS = 366

  tool_name "list_events"
  description "Events you can see that start between `from` and `to` (YYYY-MM-DD, inclusive, at most 366 days apart), " \
    "oldest first, with team, type, times and number of check-ins. Optionally only one team's or one event type's."
  scope :read
  feature :events
  input_schema(
    properties: {
      from: { type: "string", description: "First day, YYYY-MM-DD" },
      to: { type: "string", description: "Last day, YYYY-MM-DD" },
      team_id: { type: "string", description: "Only this team's events (tm_ ID)" },
      event_type_id: { type: "string", description: "Only this type of event (evtp_ ID)" },
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
            id: { type: "string" },
            name: { type: "string" },
            team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            event_type: REF_SCHEMA,
            start_time: { type: "string" },
            end_time: { type: [ "string", "null" ] },
            location: { type: [ "string", "null" ] },
            checkin_count: { type: "integer" }
          },
          required: %w[id name team event_type start_time end_time location checkin_count]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(from:, to:, team_id: nil, event_type_id: nil, limit: DEFAULT_LIMIT)
    window = date_window(from, to)
    events = ctx.policy_scope(Event).where(start_time: window)
    events = events.where(team_id: ctx.find(ctx.policy_scope(Team), team_id).id) if team_id
    events = events.where(event_type_id: event_type(event_type_id).id) if event_type_id

    result = list(events.includes(:team, :event_type).order(:start_time, :id), limit: limit) { |event| event }
    counts = Checkin.where(event_id: result[:items].map(&:id)).group(:event_id).count

    result.merge(items: result[:items].map { |event| event_json(event).merge(checkin_count: counts.fetch(event.id, 0)) })
  end

  private

  def event_json(event)
    {
      id: event.neat_id,
      name: event.name,
      team: event.team && team_json(event.team),
      event_type: { id: event.event_type.neat_id, name: event.event_type.name.to_s },
      start_time: time_json(event.start_time),
      end_time: time_json(event.end_time),
      location: event.location.presence
    }
  end

  def event_type(event_type_id)
    Mcp.find_by_neat_id(EventType, event_type_id) || not_found!
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
