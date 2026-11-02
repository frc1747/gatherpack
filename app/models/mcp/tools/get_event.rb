# One event and who checked in. The event must be in policy_scope(Event). The
# event page (EventsController#show) loads any event by ID and lists every
# check-in: policy_scope(@event.checkins) is CheckinPolicy::Scope, which
# returns all rows, and the view shows each person's name for anyone who can
# open the page. The tool is narrower on the event (policy_scope(Event)) and
# then lists all of that event's check-ins, as the page does; it leaves out
# check-in notes, a free-text field, and the check-in field responses, which
# have their own read levels. Times of check-ins are when they were made.
class Mcp::Tools::GetEvent < Mcp::Tool
  tool_name "get_event"
  description "One event you can see: team, type, times, location, description and the people checked in, " \
    "with when they checked in."
  scope :read
  feature :events
  input_schema(properties: { event_id: { type: "string", description: "The event's ID (evt_)" } }, required: [ "event_id" ])
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      team: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
      event_type: REF_SCHEMA,
      start_time: { type: "string" },
      end_time: { type: [ "string", "null" ] },
      location: { type: [ "string", "null" ] },
      description: { type: [ "string", "null" ] },
      checkin_limit: { type: [ "integer", "null" ] },
      checkin_count: { type: "integer" },
      attendees: {
        type: "array",
        items: {
          type: "object",
          properties: { checkin_id: { type: "string" }, person: REF_SCHEMA, checked_in_at: { type: "string" } },
          required: %w[checkin_id person checked_in_at]
        }
      }
    },
    required: %w[id name team event_type start_time end_time location description checkin_limit checkin_count attendees]
  )

  def call(event_id:)
    event = ctx.find(Event, event_id)
    checkins = event.checkins.includes(:person).order(:created_at, :id).to_a

    {
      id: event.neat_id,
      name: event.name,
      team: event.team && team_json(event.team),
      event_type: { id: event.event_type.neat_id, name: event.event_type.name.to_s },
      start_time: time_json(event.start_time),
      end_time: time_json(event.end_time),
      location: event.location.presence,
      description: event.description.presence,
      checkin_limit: event.checkin_limit.presence,
      checkin_count: checkins.size,
      attendees: checkins.map do |checkin|
        { checkin_id: checkin.neat_id, person: person_json(checkin.person), checked_in_at: time_json(checkin.created_at) }
      end
    }
  end
end
