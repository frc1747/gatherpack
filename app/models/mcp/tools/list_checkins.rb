# A person's check-ins in a date window, as the profile's Recent Activity
# shows their events. The person is looked up in policy_scope(Person) and
# must pass PersonPolicy#show? (PeopleController#set_person, and
# PersonPolicy#recent_activity? is an alias of show?). The page lists
# policy_scope(@person.events), so only check-ins at events in
# policy_scope(Event) are returned. CheckinPolicy::Scope returns every row and
# isn't used. The window is on the event's start time, from and to inclusive,
# at most 366 days. Notes and field responses are left out.
class Mcp::Tools::ListCheckins < Mcp::Tool
  MAX_WINDOW_DAYS = 366

  tool_name "list_checkins"
  description "A person's check-ins at events you can see, for events starting between `from` and `to` " \
    "(YYYY-MM-DD, inclusive, at most 366 days apart), newest event first."
  scope :read
  feature :events
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      from: { type: "string", description: "First day, YYYY-MM-DD" },
      to: { type: "string", description: "Last day, YYYY-MM-DD" },
      limit: limit_property
    },
    required: %w[person_id from to]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            checkin_id: { type: "string" },
            event: {
              type: "object",
              properties: { id: { type: "string" }, name: { type: "string" }, start_time: { type: "string" } },
              required: %w[id name start_time]
            },
            checked_in_at: { type: "string" }
          },
          required: %w[checkin_id event checked_in_at]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(person_id:, from:, to:, limit: DEFAULT_LIMIT)
    window = date_window(from, to)
    person = ctx.find(Person, person_id)
    ctx.authorize!(person, :show?)

    checkins = person.checkins.joins(:event).where(events: { id: ctx.policy_scope(Event).select(:id), start_time: window })
      .includes(:event).order("events.start_time DESC", :id)

    list(checkins, limit: limit) do |checkin|
      {
        checkin_id: checkin.neat_id,
        event: { id: checkin.event.neat_id, name: checkin.event.name, start_time: time_json(checkin.event.start_time) },
        checked_in_at: time_json(checkin.created_at)
      }
    end
  end

  private

  # from.beginning_of_day..to.end_of_day in the app's time zone.
  def date_window(from, to)
    first = parse_date(from, "from")
    last = parse_date(to, "to")
    invalid_argument!("to can't be before from") if last < first
    invalid_argument!("The window can be at most #{MAX_WINDOW_DAYS} days") if (last - first).to_i > MAX_WINDOW_DAYS

    first.in_time_zone.beginning_of_day..last.in_time_zone.end_of_day
  end

  def parse_date(value, name)
    Date.iso8601(value)
  rescue Date::Error
    invalid_argument!("#{name} must be a date like 2026-03-31")
  end
end
