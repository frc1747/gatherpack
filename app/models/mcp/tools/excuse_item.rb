# Excuses a person from an item, or from one meeting of an attendance item, as the report's Excuse
# does (ChecklistExcusesController#create, and ChecklistMeetingExcuses#create_meeting_excuse
# when there is an event_id).
#
# Mirrors: the checklist is found as the checklists page finds it (policy_scope(Checklist)), then
# the item in it, the person among those it covers (Checklists.people_covered_by), the excuse built
# with reason and expires_on and created_by the viewer's person, and authorize create?
# (ChecklistExcusePolicy: managers of the checklist's team and above, and admins, on a checklist
# that isn't archived; never themselves or a relative, named in the refusal as the model names it:
# "Another manager needs to excuse you or a relative"). Anyone who can see the checklist but isn't a
# manager is refused before the person is looked up, so they can't learn who it covers. With an
# event_id, only an attendance item's meetings that haven't an excuse in force for this person
# take it ("Pick one of this item's meetings" otherwise). The model's validations (a reason)
# come back as invalid-argument errors. The reason is a note about a member: masked in the call
# log. Needs the checklists feature.
class Mcp::Tools::ExcuseItem < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "excuse_item"
  description "Excuse a person the checklist covers from one of its items, or from one meeting of an attendance item (event_id), with a reason, as the report's Excuse does. " \
    "Only managers of the checklist's team and above, and admins, and not for themselves or a relative: that is \"Not allowed\". " \
    "A checklist you can't see, or an item or person it doesn't have, is \"Not found\". Returns the excuse."
  scope :write
  feature :checklists
  mask_argument :reason
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      item_id: { type: "string", description: "The item (chli_)" },
      person_id: { type: "string", description: "A person the checklist covers (per_)" },
      reason: { type: "string", description: "Why; shown to managers and admins" },
      expires_on: { type: "string", format: "date", description: "Last day the excuse applies (YYYY-MM-DD). Optional: no end." },
      event_id: { type: "string", description: "Excuse just this meeting of an attendance item (evt_). Optional." }
    },
    required: %w[checklist_id item_id person_id reason],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      excuse_id: { type: "string" },
      item: Mcp::ChecklistRecords::ITEM_REF_SCHEMA,
      person: Mcp::Tool::REF_SCHEMA,
      event: { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ] },
      expires_on: { type: %w[string null] }
    },
    required: %w[excuse_id item person event expires_on]
  )

  def call(checklist_id:, item_id:, person_id:, reason:, expires_on: nil, event_id: nil)
    checklist = find_checklist(checklist_id)
    item = find_item(checklist, item_id)
    refuse! unless checklist.manager?(ctx.person)

    person = find_covered_person(checklist, person_id)
    excuse = ChecklistExcuse.new(reason: reason, expires_on: parse_date(expires_on), item: item, person: person, created_by: ctx.person)
    refuse!((ChecklistExcuse::SELF_REASON if self_or_relative?(person))) unless ctx.allowed?(excuse, :create?)

    excuse.event = meeting(checklist, item, person, event_id) if event_id
    invalid_argument!(excuse.errors.full_messages.to_sentence) unless excuse.save

    changed!(excuse)
    {
      excuse_id: excuse.neat_id,
      item: item_ref_json(item),
      person: person_json(person),
      event: excuse.event && { id: excuse.event.neat_id, name: excuse.event.name.to_s },
      expires_on: date_json(excuse.expires_on)
    }
  end

  private

  def self_or_relative?(person)
    person.id == ctx.person.id || Checklists.related?(ctx.person, person)
  end

  def parse_date(value)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    invalid_argument!("expires_on must be a date, YYYY-MM-DD")
  end

  # One of the attendance item's held meetings the person isn't already excused from.
  def meeting(checklist, item, person, event_id)
    event = Mcp.find_by_neat_id(Event, event_id)
    found = event && meetings(checklist, item, person).find { |candidate| candidate.id == event.id }
    invalid_argument!("Pick one of this item's meetings") unless found

    found
  end

  def meetings(checklist, item, person)
    return [] unless item.kind_class == Checklists::Kinds::Attendance

    excused = ChecklistExcuse.where(item: item, person: person).where.not(event_id: nil).in_force(Date.current).map(&:event_id)
    Checklists::Kinds::Attendance.new(item, Checklists::Context.new(checklist)).meetings.reject { |meeting| excused.include?(meeting.id) }
  end
end
