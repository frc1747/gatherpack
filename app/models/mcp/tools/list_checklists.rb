# The checklists the viewer can see, as /checklists lists them (ChecklistsController#index:
# policy_scope(Checklist), by title, archived ones left out unless asked): those they run, and
# those with results they may see (their own, their wards', the people they lead, through a
# grant or an item's level). A draft shows only to the people who run it. organizer says whether
# the viewer runs it (Checklist#organizer?), which is who sees everyone's rows and may adjust,
# excuse and copy. Needs the checklists feature.
class Mcp::Tools::ListChecklists < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "list_checklists"
  description "Checklists you can see (ones you run, and ones with results you may see), by title, with team, status, dates " \
    "and whether you run it. Archived ones are left out unless include_archived."
  scope :read
  feature :checklists
  input_schema(
    properties: {
      include_archived: { type: "boolean", description: "Also list archived checklists (default false)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::ChecklistRecords::CHECKLIST_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(include_archived: false, limit: DEFAULT_LIMIT)
    checklists = ctx.policy_scope(Checklist).includes(:team).order(:title, :id)
    checklists = checklists.where.not(status: :archived) unless include_archived
    list(checklists, limit: limit) { |checklist| checklist_json(checklist) }
  end
end
