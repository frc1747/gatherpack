# Removes a check-in, as CheckinsController#destroy (Checkout) does (line 44): set_event
# (line 94), set_checkin (line 85, authorize destroy?), destroy!. CheckinPolicy doesn't define
# destroy?, so it's ApplicationPolicy's, which calls CheckinPolicy#update?: the person checked
# in, admins, and the managers of the event's team. A locked event doesn't change that. Whatever
# a connector does on a check-in's removal runs as on the page, so sign-ups it fulfilled stay
# fulfilled.
class Mcp::Tools::RemoveCheckin < Mcp::Tool
  include Mcp::CheckinRecords

  tool_name "remove_checkin"
  description "Remove a check-in, as Checkout does on the event's page. A check-in you can see but not change is \"Not allowed\". Returns what was removed."
  scope :write
  feature :events
  destructive
  input_schema(
    properties: { checkin_id: { type: "string", description: "The check-in's ID (cki_)" } },
    required: %w[checkin_id]
  )
  output_schema(
    type: "object",
    properties: Mcp::CheckinRecords::REF_SCHEMA.merge(removed: { type: "boolean" }),
    required: %w[id person event removed]
  )

  def call(checkin_id:)
    checkin = find_checkin(checkin_id)
    ctx.authorize!(checkin, :destroy?)
    checkin.destroy!

    changed!(checkin)
    checkin_ref_json(checkin).merge(removed: true)
  end
end
