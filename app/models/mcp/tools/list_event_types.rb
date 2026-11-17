# The event types to choose from when creating an event: what the new event form
# lists (events/_form's event_type association, every type; the table has no team
# column). Gated on EventPolicy#new?, the check on EventsController#new that opens
# the form: admins and anyone managing a team.
class Mcp::Tools::ListEventTypes < Mcp::Tool
  tool_name "list_event_types"
  description "The event types you can choose from when creating an event, by name. Admins and team managers only."
  scope :read
  feature :events
  input_schema(properties: { limit: limit_property })
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: REF_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    ctx.authorize!(Event.new, :new?)

    list(EventType.order(:name, :id), limit: limit) { |type| { id: type.neat_id, name: type.name } }
  end
end
