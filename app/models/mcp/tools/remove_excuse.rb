# Removes an excuse, as the report's "Remove" does (ChecklistExcusesController#destroy).
#
# Mirrors: the checklist is found as the checklists page finds it (policy_scope(Checklist)), the
# excuse among its items' excuses, authorize destroy? (ChecklistExcusePolicy: managers of the
# checklist's team and above, and admins, on a checklist that isn't archived), destroy!. The
# excuse's ID is the excuse_id that checklist_status and checklist_results give a manager. Needs
# the checklists feature.
class Mcp::Tools::RemoveExcuse < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "remove_excuse"
  description "Remove an excuse from a checklist item, as Remove on the report does, by the excuse_id checklist_results shows a manager. " \
    "Only managers of the checklist's team and above, and admins: that is \"Not allowed\"; a checklist or excuse you can't see is \"Not found\". " \
    "Returns what was removed."
  scope :write
  feature :checklists
  destructive
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      excuse_id: { type: "string", description: "The excuse's ID (chlx_)" }
    },
    required: %w[checklist_id excuse_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      removed_excuse_id: { type: "string" },
      item: Mcp::ChecklistRecords::ITEM_REF_SCHEMA,
      person: Mcp::Tool::REF_SCHEMA
    },
    required: %w[removed_excuse_id item person]
  )

  def call(checklist_id:, excuse_id:)
    checklist = find_checklist(checklist_id)
    excuse = Mcp.find_by_neat_id(ChecklistExcuse.where(item_id: checklist.checklist_items.select(:id)), excuse_id) || not_found!
    ctx.authorize!(excuse, :destroy?)

    excuse.destroy!

    changed!(excuse)
    { removed_excuse_id: excuse.neat_id, item: item_ref_json(excuse.item), person: person_json(excuse.person) }
  end
end
