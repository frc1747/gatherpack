# Removes an event, as EventsController#destroy does (line 73): set_event (line 80), then
# destroy!. EventPolicy doesn't define destroy?, so it's ApplicationPolicy's, which calls
# EventPolicy#update?: admins and managers of the event's team, ancestors' managers included.
# The event is looked up in policy_scope(Event), as UpdateEvent's comment explains.
#
# Check-ins refuse it, with the count, while has_many :checkins has no dependent option: the
# page's destroy! fails on the foreign key then, and that's the only refusal the page doesn't
# give in words. A build whose Event deletes its check-ins (dependent: set) removes them here
# too, as its page does. The same failure from any other table (a connector's) is refused
# without a count. PaperTrail writes the destroy row to its own
# database first, so the transaction there takes it back; the page's delete leaves it.
class Mcp::Tools::RemoveEvent < Mcp::Tool
  include Mcp::EventRecords

  tool_name "remove_event"
  description "Delete an event, as Delete does on the event's page. Where the page can't delete an event's check-ins, an event with check-ins " \
    "can't be removed and the refusal gives the count; one you can see but not edit is \"Not allowed\". Returns what was removed."
  scope :write
  feature :events
  destructive
  input_schema(
    properties: { event_id: { type: "string", description: "The event's ID (evt_)" } },
    required: %w[event_id]
  )
  output_schema(Mcp::EventRecords::SCHEMA.merge(
    properties: Mcp::EventRecords::SCHEMA[:properties].merge(removed: { type: "boolean" }),
    required: Mcp::EventRecords::SCHEMA[:required] + %w[removed]
  ))

  def call(event_id:)
    event = ctx.find(Event, event_id)
    ctx.authorize!(event, :destroy?)
    unless self.class.checkins_go_with_event?
      count = event.checkins.count
      invalid_argument!("This event has #{count} #{"check-in".pluralize(count)}, so it can't be removed") if count.positive?
    end

    shown = event_json(event)
    AuditLog.transaction { event.destroy! }

    changed!(event)
    shown.merge(removed: true)
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed
    invalid_argument!("Other records still refer to this event, so it can't be removed")
  end

  def self.checkins_go_with_event?
    Event.reflect_on_association(:checkins).options[:dependent].present?
  end
end
