# Checks a person in to an event, as CheckinsController#create does.
#
# Mirrors: set_event (line 94, the event in policy_scope(Event), so non-admins can't reach
# team-less events), create (lines 22-25: build through the event, authorize create?, set
# created_by to the viewer, save). CheckinPolicy#create? lets anyone who reaches the event
# check anyone in, unless it's locked: then only admins and the team's managers. The model's
# check-in limit and duplicate validations come back as invalid-argument errors.
#
# Check-in fields have no "required" setting (checkin_fields holds a name and a permission),
# so nothing has to be refused for them: Checkin#refresh_fields creates a blank response per
# field, as the page does for a form left empty. Notes and field responses aren't inputs.
#
# Narrower than the page in one way: the person must be in policy_scope(Person). The POST
# doesn't check the person, but its form offers only those people ("people" search scope).
class Mcp::Tools::RecordCheckin < Mcp::Tool
  tool_name "record_checkin"
  description "Check a person in to an event. Admins can check in anyone. The event team's managers can check in themselves and people they manage, locked events included. " \
    "Anyone else can check in only themselves, and not on a locked event. Returns the new check-in."
  scope :write
  feature :events
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      event_id: { type: "string", description: "The event's ID (evt_)" }
    },
    required: %w[person_id event_id]
  )
  output_schema(
    type: "object",
    properties: { id: { type: "string" }, person: REF_SCHEMA, event: REF_SCHEMA },
    required: %w[id person event]
  )

  def call(person_id:, event_id:)
    person = ctx.find(Person, person_id)
    event = ctx.find(Event, event_id)
    checkin = event.checkins.build(person: person)
    ctx.authorize!(checkin, :create?)
    checkin.created_by = ctx.person
    invalid_argument!(checkin.errors.full_messages.to_sentence) unless checkin.save

    changed!(checkin)
    { id: checkin.neat_id, person: person_json(person), event: { id: event.neat_id, name: event.name } }
  end
end
