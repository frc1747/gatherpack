# What remove_checkin and update_checkin share: finding a check-in as
# CheckinsController does, through its event. set_event (line 94) needs the event in
# policy_scope(Event); set_checkin's policy_scope(@event.checkins) (line 85) returns every
# row, so the event is the gate.
module Mcp::CheckinRecords
  REF_SCHEMA = {
    id: { type: "string" },
    person: Mcp::Tool::REF_SCHEMA,
    event: Mcp::Tool::REF_SCHEMA
  }.freeze

  private

  def find_checkin(checkin_id)
    ctx.find(Checkin.where(event_id: ctx.policy_scope(Event).select(:id)), checkin_id)
  end

  def checkin_ref_json(checkin)
    { id: checkin.neat_id, person: person_json(checkin.person), event: { id: checkin.event.neat_id, name: checkin.event.name } }
  end
end
