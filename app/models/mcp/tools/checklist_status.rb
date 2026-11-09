# One person's results, as the viewer may see them: the checklist's report row for that person
# (with checklist_id; ChecklistsController#show through Checklists.status_for), or every checklist
# covering them (the person's Checklists tab, PersonChecklistsController#show:
# policy_scope(Person) and PersonPolicy#show?, then Checklists.checklist_for).
#
# With checklist_id the checklist must be one the viewer can see (policy_scope(Checklist)), and the
# person must be a row they may see in it; otherwise "Not found", which is also what an unknown
# person is. Without it, the person must be one whose page the viewer may open. Visibility (who
# sees which items, and how much of each) is applied inside Checklists.status_for, so a summary,
# detail, number or fix link appears only where the page would show it. person_id defaults to the
# viewer. Needs the checklists feature.
class Mcp::Tools::ChecklistStatus < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "checklist_status"
  description "A person's results on checklists, as you may see them: Complete, In Progress, Not Started or Not counted overall and per item, " \
    "with what to do next. With checklist_id, that checklist; without, every checklist that covers the person. " \
    "person_id defaults to you. A person or checklist you can't see is \"Not found\"."
  scope :read
  feature :checklists
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person (per_). Default: you." },
      checklist_id: { type: "string", description: "Only this checklist (chkl_). Optional." }
    }
  )
  output_schema(
    type: "object",
    properties: {
      person: Mcp::Tool::REF_SCHEMA,
      checklists: {
        type: "array",
        items: {
          type: "object",
          properties: {
            checklist: Mcp::ChecklistRecords::CHECKLIST_SCHEMA,
            overall: { anyOf: [ Mcp::ChecklistRecords::CELL_SCHEMA, { type: "null" } ] },
            items: { type: "array", items: Mcp::ChecklistRecords::CELL_SCHEMA }
          },
          required: %w[checklist overall items]
        }
      }
    },
    required: %w[person checklists]
  )

  def call(person_id: nil, checklist_id: nil)
    person = person_id ? Mcp.find_by_neat_id(Person, person_id) || not_found! : ctx.person
    entries = checklist_id ? [ one_checklist(person, checklist_id) ] : all_checklists(person)

    { person: person_json(person), checklists: entries.map { |checklist, status| { checklist: checklist_json(checklist) }.merge(status_json(status)) } }
  end

  private

  def one_checklist(person, checklist_id)
    checklist = find_checklist(checklist_id)
    status = Checklists.status_for(checklist, [ person ], viewer: ctx.person)[person.id] || not_found!
    [ checklist, status ]
  end

  def all_checklists(person)
    not_found! unless ctx.policy_scope(Person).exists?(id: person.id)
    ctx.authorize!(person, :show?)
    Checklists.checklist_for(person, viewer: ctx.person)
  end
end
