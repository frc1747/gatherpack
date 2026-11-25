# Takes a snapshot of a checklist, as "Take Snapshot" does (ChecklistListsController#create): a
# read-only record of everyone it covers, with their statuses and the checklist's configuration,
# for a decision such as a trip roster.
#
# Mirrors: set_checklist (policy_scope(Checklist)), authorize on a new snapshot of it (create?:
# the checklist's organizers, and nothing on an archived checklist), then ChecklistList.record!
# with the viewer's person and the note. Returns the snapshot's ID, when and how many people it holds;
# the page shows the rows. The note can say anything: masked in the call log. Needs the
# checklists feature.
class Mcp::Tools::RecordList < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "record_list"
  description "Take a snapshot of a checklist now: a fixed record of everyone it covers and their statuses, as Take Snapshot does. " \
    "Only the checklist's organizers, and not once it is archived: that is \"Not allowed\"; a checklist you can't see is \"Not found\". " \
    "Returns the snapshot."
  scope :write
  feature :checklists
  mask_argument :note
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      note: { type: "string", description: "What the snapshot is for. Optional." }
    },
    required: %w[checklist_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      checklist: Mcp::Tool::REF_SCHEMA,
      recorded_at: { type: "string" },
      note: { type: %w[string null] },
      people: { type: "integer" }
    },
    required: %w[id checklist recorded_at note people]
  )

  def call(checklist_id:, note: nil)
    checklist = find_checklist(checklist_id)
    ctx.authorize!(ChecklistList.new(checklist: checklist), :create?)

    list = ChecklistList.record!(checklist, by: ctx.person, note: note)

    changed!(list)
    { id: list.neat_id, checklist: { id: checklist.neat_id, name: checklist.title }, recorded_at: time_json(list.recorded_at),
      note: list.note, people: list.rows.size }
  end
end
