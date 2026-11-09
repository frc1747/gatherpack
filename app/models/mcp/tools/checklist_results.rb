# A checklist's rows as its report shows the viewer (ChecklistsController#show:
# Checklists::Report.new(checklist, viewer, as_of:)): a row per person the viewer may see, the
# overall and each item's result at the level the viewer may see, with a count item's numbers in
# measures. The checklist must be one the viewer can see (policy_scope(Checklist)), otherwise
# "Not found". Rows are ordered as the report does (not complete first, then by what's left, then
# name), at most `limit`; the viewer's own and their wards' rows come first as "Your family" when
# they see others too. as_of (a date) recomputes as of then and stores nothing, and the page offers
# it only to those who may change the checklist (ChecklistPolicy#update?: its organizers, not once
# it is archived), so for anyone else it is ignored. A person the viewer
# sees no part of isn't in rows at all. Needs the checklists feature.
class Mcp::Tools::ChecklistResults < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "checklist_results"
  description "A checklist's results for everyone, as its report page shows you: one row per person you may see, with the overall and each item " \
    "(count items carry confirmed, planned, owed and remaining in measures). A checklist you can't see is \"Not found\". " \
    "as_of only applies if you run the checklist and it isn't archived."
  scope :read
  feature :checklists
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      as_of: { type: "string", format: "date", description: "Compute as of this date (YYYY-MM-DD); only for those who run the checklist" },
      limit: limit_property
    },
    required: %w[checklist_id]
  )
  output_schema(
    type: "object",
    properties: {
      checklist: Mcp::ChecklistRecords::CHECKLIST_SCHEMA,
      counts: { type: "object", description: "How many people have each overall status among all rows seen" },
      rows: {
        type: "array",
        items: {
          type: "object",
          properties: {
            person: Mcp::Tool::REF_SCHEMA,
            family: { type: "boolean", description: "The viewer or one of their wards" },
            overall: { anyOf: [ Mcp::ChecklistRecords::CELL_SCHEMA, { type: "null" } ] },
            items: { type: "array", items: Mcp::ChecklistRecords::CELL_SCHEMA }
          },
          required: %w[person family overall items]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[checklist counts rows truncated]
  )

  def call(checklist_id:, as_of: nil, limit: DEFAULT_LIMIT)
    checklist = find_checklist(checklist_id)
    report = Checklists::Report.new(checklist, ctx.person, as_of: (parse_date(as_of) if ctx.allowed?(checklist, :update?)))
    rows = report.sections.flat_map { |_, statuses| statuses }
    limit = limit.to_i.clamp(1, MAX_LIMIT)

    {
      checklist: checklist_json(checklist),
      counts: report.counts,
      rows: rows.first(limit).map { |status| { person: person_json(report.people.fetch(status.person_id)), family: report.family_ids.include?(status.person_id) }.merge(status_json(status)) },
      truncated: rows.size > limit
    }
  end

  private

  def parse_date(value)
    Date.iso8601(value) if value.present?
  rescue Date::Error
    invalid_argument!("as_of must be a date, YYYY-MM-DD")
  end
end
