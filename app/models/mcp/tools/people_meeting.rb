# The people a checklist's report shows the viewer whose overall status is this one: the report's
# overall column filter, as Checklists.people_meeting does for features that use a checklist as a
# test, but limited to the rows the viewer may see (Checklists::Report#statuses), so it tells
# them nothing the report page wouldn't. The checklist must be one the viewer can see, otherwise
# "Not found". A row whose overall the viewer can't see isn't matched by a specific status. not_done
# is the report's "isn't Complete" (In Progress, Not Started and Not counted together), which also keeps a row
# whose overall the viewer can't see, as the page's filter does; those rows have blank text. Needs the checklists feature.
class Mcp::Tools::PeopleMeeting < Mcp::Tool
  include Mcp::ChecklistRecords

  STATUSES = (Mcp::ChecklistRecords::STATUSES + %w[not_done]).freeze

  tool_name "people_meeting"
  description "People on a checklist whose overall status is met (Complete), pending (In Progress), not_met (Not Started), exempt (Not counted), " \
    "or not_done (anything but Complete), among the rows its report shows you. A checklist you can't see is \"Not found\"."
  scope :read
  feature :checklists
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      status: { type: "string", enum: STATUSES, description: "Overall status to match (default met)" },
      limit: limit_property
    },
    required: %w[checklist_id]
  )
  output_schema(
    type: "object",
    properties: {
      checklist: Mcp::ChecklistRecords::CHECKLIST_SCHEMA,
      status: { type: "string" },
      people: {
        type: "array",
        items: {
          type: "object",
          properties: { person: Mcp::Tool::REF_SCHEMA, text: { type: "string" } },
          required: %w[person text]
        }
      },
      total: { type: "integer" },
      truncated: { type: "boolean" }
    },
    required: %w[checklist status people total truncated]
  )

  def call(checklist_id:, status: "met", limit: DEFAULT_LIMIT)
    checklist = find_checklist(checklist_id)
    report = Checklists::Report.new(checklist, ctx.person)
    matches = report.statuses.values.select { |entry| matches?(entry, status) }
      .sort_by { |entry| [ report.name(entry.person_id).to_s, entry.person_id ] }
    limit = limit.to_i.clamp(1, MAX_LIMIT)

    {
      checklist: checklist_json(checklist),
      status: status,
      people: matches.first(limit).map { |entry| { person: person_json(report.people.fetch(entry.person_id)), text: entry.overall&.text.to_s } },
      total: matches.size,
      truncated: matches.size > limit
    }
  end

  private

  # not_done is the report's filter, which keeps a row whose overall the viewer can't see.
  def matches?(entry, status)
    overall = entry.overall&.status
    status == "not_done" ? overall != "met" : overall == status
  end
end
