# What the event tools share: an event in get_event's shape. checkin_id is what
# remove_checkin and update_checkin take, null unless the viewer may remove that check-in
# (destroy?, the check the page's Checkout link makes, _checkin line 14).
module Mcp::EventRecords
  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      team: { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ] },
      event_type: Mcp::Tool::REF_SCHEMA,
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
          properties: { checkin_id: { type: %w[string null] }, person: Mcp::Tool::REF_SCHEMA },
          required: %w[checkin_id person]
        }
      },
      attendees_truncated: { type: "boolean" }
    },
    required: %w[id name team event_type start_time end_time location description checkin_limit checkin_count attendees attendees_truncated]
  }.freeze

  private

  def event_json(event, limit: Mcp::Tool::DEFAULT_LIMIT)
    attendees = list(event.checkins.includes(:person).joins(:person).order("people.last_name", "people.first_name", :id), limit: limit) do |checkin|
      { checkin_id: ctx.allowed?(checkin, :destroy?) ? checkin.neat_id : nil, person: person_json(checkin.person) }
    end

    {
      id: event.neat_id,
      name: event.name,
      team: event.team && team_json(event.team),
      event_type: { id: event.event_type.neat_id, name: event.event_type.name.to_s },
      start_time: time_json(event.start_time),
      end_time: time_json(event.end_time),
      location: event.location.presence,
      description: event.description.presence,
      checkin_limit: event.checkin_limit.to_i.positive? ? event.checkin_limit : nil,
      checkin_count: event.checkins.count,
      attendees: attendees[:items],
      attendees_truncated: attendees[:truncated]
    }
  end
end
