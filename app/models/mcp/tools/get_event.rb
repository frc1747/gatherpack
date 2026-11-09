# One event and who checked in. The event must be in policy_scope(Event). The
# event page (EventsController#show) loads any event by ID and lists every
# check-in: policy_scope(@event.checkins) is CheckinPolicy::Scope, which
# returns all rows, and the view shows each person's name for anyone who can
# open the page. The tool is narrower on the event (policy_scope(Event)) and
# then lists that event's check-ins, as the page does; it leaves out
# check-in notes, a free-text field, and the check-in field responses, which
# have their own read levels. When a check-in was made appears on no page,
# so it isn't returned. Attendees are capped at `limit` (default 25, at most
# 100) in name order, with attendees_truncated; checkin_count is the full count.
# checkin_id is null unless the viewer may remove that check-in (Mcp::EventRecords).
class Mcp::Tools::GetEvent < Mcp::Tool
  include Mcp::EventRecords

  tool_name "get_event"
  description "One event you can see: team, type, times, location, description and the people checked in " \
    "(at most `limit`, by name; checkin_count is the full number). " \
    "Each check-in's ID is given only where you may remove it."
  scope :read
  feature :events
  input_schema(
    properties: { event_id: { type: "string", description: "The event's ID (evt_)" }, limit: limit_property },
    required: [ "event_id" ]
  )
  output_schema(Mcp::EventRecords::SCHEMA)

  def call(event_id:, limit: DEFAULT_LIMIT)
    event_json(ctx.find(Event, event_id), limit: limit)
  end
end
