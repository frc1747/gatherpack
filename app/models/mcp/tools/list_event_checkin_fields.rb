# The check-in fields of an event's type: the questions its check-in form asks
# (checkins/_form line 7), and the fields the event's print and arrange screens offer. The
# event must be in policy_scope(Event). Fields, not anyone's answers. permission is who
# may answer (CheckinFieldResponse#permission_check).
class Mcp::Tools::ListEventCheckinFields < Mcp::Tool
  tool_name "list_event_checkin_fields"
  description "The check-in fields of an event you can see: names and who may answer them, not anyone's answers. An event you can't see is \"Not found\"."
  scope :read
  feature :events
  input_schema(
    properties: { event_id: { type: "string", description: "The event's ID (evt_)" }, limit: limit_property },
    required: [ "event_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: { id: { type: "string" }, name: { type: "string" }, permission: { type: "string" } },
          required: %w[id name permission]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(event_id:, limit: DEFAULT_LIMIT)
    event = ctx.find(Event, event_id)

    list(event.event_type.checkin_fields.order(:name, :id), limit: limit) do |field|
      { id: field.neat_id, name: field.name.to_s, permission: field.permission }
    end
  end
end
