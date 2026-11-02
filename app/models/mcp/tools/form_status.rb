# Who a form asks and where each person stands, as the form's status page and
# results page list them (FormsController#show and #results, both authorized
# with FormPolicy#show?/#results?; the page loads any form by ID, so a form the
# policy scope hides still shows to someone who can see its results). Gate:
# FormPolicy#results?. The people are FormReport's rows for the viewer, which
# is Form#readable_subjects_for: only people whose response the viewer may read
# (FormAccess#can_read?, the same rule as FormResponsePolicy#show?), so the
# counts below cover those people only. A form's anonymous totals
# (FormPolicy#tally?) aren't offered. assigned counts the people the form asks
# now; submitted those with a submission in effect, with its time. Status is the
# page's own: not_started, draft, waiting (submitted, waiting for a signature),
# complete, needs_reconfirmation, withdrawn, no_longer_asked. Differs from the
# page in offering an optional status filter, so "who hasn't" fits under the limit.
class Mcp::Tools::FormStatus < Mcp::Tool
  tool_name "form_status"
  description "Who a form asks and who has answered: counts by status, and the people (by last name) with their status and, " \
    "when an answer is in effect, when it was submitted. Only people whose response you may read are included. " \
    "Statuses: #{FormReport::STATUSES.join(", ")}; waiting means submitted but waiting for a signature. " \
    "Optionally only people with one status."
  scope :read
  feature :forms
  input_schema(
    properties: {
      form_id: { type: "string", description: "The form (frm_ ID)" },
      status: { type: "string", enum: FormReport::STATUSES, description: "Only people with this status" },
      limit: limit_property
    },
    required: %w[form_id]
  )
  output_schema(
    type: "object",
    properties: {
      form: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          status: { type: "string" },
          closes_at: { type: [ "string", "null" ] }
        },
        required: %w[id title status closes_at]
      },
      counts: {
        type: "object",
        properties: {
          assigned: { type: "integer" },
          submitted: { type: "integer" },
          by_status: { type: "object", additionalProperties: { type: "integer" } }
        },
        required: %w[assigned submitted by_status]
      },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            person: REF_SCHEMA,
            status: { type: "string" },
            submitted_at: { type: [ "string", "null" ] }
          },
          required: %w[person status submitted_at]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[form counts items truncated]
  )

  def call(form_id:, status: nil, limit: DEFAULT_LIMIT)
    form = ctx.find(Form.all, form_id)
    ctx.authorize!(form, :results?)

    report = FormReport.new(form, viewer: ctx.person)
    rows = report.rows
    shown = status ? rows.select { |row| row.status == status } : rows
    limit = limit.to_i.clamp(1, MAX_LIMIT)

    {
      form: { id: form.neat_id, title: form.title, status: form.status, closes_at: time_json(form.closes_at) },
      counts: {
        assigned: rows.count { |row| row.access.in_audience? },
        submitted: rows.count { |row| row.access.in_audience? && row.response&.active_submission },
        by_status: report.status_counts
      },
      items: shown.first(limit).map { |row| row_json(row) },
      truncated: shown.size > limit
    }
  end

  private

  def row_json(row)
    { person: person_json(row.person), status: row.status, submitted_at: time_json(row.submission&.submitted_at) }
  end
end
