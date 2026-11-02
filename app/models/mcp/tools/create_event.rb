# Creates an event, as EventsController#create does.
#
# Mirrors: create (lines 53-55: build from permitted attributes, authorize create?, save).
# EventPolicy#create? is admins and managers of the event's team, ancestors' managers included.
# The attributes are a subset of event_params (name, start_time, end_time, location,
# event_type_id, team_id). The event form offers every event type to anyone who can open it
# (EventTypePolicy::Scope returns every row), so the type is looked up without a policy.
#
# Narrower than the page, as the spec asks: the team is required and must be in
# policy_scope(Team) (the page lets an admin leave it blank, and non-admins never see a
# team-less event); ends_at is required and must be after starts_at (the model only refuses
# an end before the start). Times are ISO 8601; without an offset, they're in the app's time zone.
class Mcp::Tools::CreateEvent < Mcp::Tool
  ISO8601_TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(?<offset>Z|[+-]\d{2}(:?\d{2})?)?\z/

  tool_name "create_event"
  description "Create an event for a team you manage. starts_at and ends_at are ISO 8601 date-times " \
    "(like 2026-03-31T18:00:00, in the app's time zone unless they carry an offset). Returns the new event."
  scope :write
  feature :events
  input_schema(
    properties: {
      team_id: { type: "string", description: "The team's ID (tm_)" },
      event_type_id: { type: "string", description: "The event type's ID (evtp_), from list_event_types" },
      name: { type: "string", description: "The event's name" },
      starts_at: { type: "string", description: "Start, ISO 8601 date-time" },
      ends_at: { type: "string", description: "End, ISO 8601 date-time, after starts_at" },
      location: { type: "string", description: "Where it is" }
    },
    required: %w[team_id event_type_id name starts_at ends_at]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      team: REF_SCHEMA,
      event_type: REF_SCHEMA,
      start_time: { type: "string" },
      end_time: { type: "string" },
      location: { type: [ "string", "null" ] }
    },
    required: %w[id name team event_type start_time end_time location]
  )

  def call(team_id:, event_type_id:, name:, starts_at:, ends_at:, location: nil)
    team = ctx.find(Team, team_id)
    event_type = ctx.find(EventType.all, event_type_id)
    event = Event.new(team: team, event_type: event_type, name: name, location: location)
    ctx.authorize!(event, :create?)

    event.start_time = parse_time(starts_at, "starts_at")
    event.end_time = parse_time(ends_at, "ends_at")
    invalid_argument!("ends_at must be after starts_at") unless event.end_time > event.start_time
    invalid_argument!(event.errors.full_messages.to_sentence) unless event.save

    changed!(event)
    {
      id: event.neat_id,
      name: event.name,
      team: team_json(team),
      event_type: { id: event_type.neat_id, name: event_type.name },
      start_time: time_json(event.start_time),
      end_time: time_json(event.end_time),
      location: event.location.presence
    }
  end

  private

  # Date.iso8601 catches days like February 31, which Time.zone.iso8601 rolls over.
  # Date._iso8601 finds no offset in one out of range, like +24:00, and Time.zone.iso8601
  # would then read the time as local.
  def parse_time(value, name)
    match = value.match(ISO8601_TIME)
    raise ArgumentError if match.nil? || (match[:offset] && Date._iso8601(value)[:offset].nil?)

    Date.iso8601(value.first(10))
    Time.zone.iso8601(value)
  rescue ArgumentError
    invalid_argument!("#{name} must be an ISO 8601 date-time like 2026-03-31T18:00:00")
  end
end
