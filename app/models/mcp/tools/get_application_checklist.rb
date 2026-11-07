# An application's checklist as managers see it beside the application
# (app/views/intake/membership_applications/_details and _checklist): "4 of 6 done", what it
# is waiting for, each item with its status, summary and who has to do it, and whether
# approval waits. Shown to people who decide the application (policy update?, as the
# partial's `decides`), so the applicant gets "Not allowed" and anyone who can't see the
# application "Not found". The statuses are Intake::ApplicationChecklists#status_for,
# which the page uses: what the viewer may see (Checklists::Visibility), and nothing when the
# application has no checklist, the checklists feature is off, the applicant isn't covered or
# the viewer sees none of it. Then checklist is null.
class Mcp::Tools::GetApplicationChecklist < Mcp::Tool
  include Mcp::MembershipApplicationRecords

  ITEM_SCHEMA = {
    type: "object",
    properties: {
      label: { type: "string" },
      status: { type: "string", enum: Checklists::STATUSES },
      text: { type: "string", description: "The word the page shows" },
      summary: { type: %w[string null], description: "Only where the viewer sees the item in full" },
      excused_by: { type: %w[string null] },
      to_do: { type: %w[string null], description: "Who has to act, as the page says it (\"Riley or a guardian\", \"a leader\")" }
    },
    required: %w[label status text summary excused_by to_do]
  }.freeze

  tool_name "get_application_checklist"
  description "An application's checklist, as managers see it beside the application: how many items are done, what it is waiting for, " \
    "each item with who has to act, and whether approval waits for it. checklist is null when there is nothing to show."
  scope :read
  feature :intake
  input_schema(
    properties: { membership_application_id: { type: "string", description: "The application's ID (ma_)" } },
    required: %w[membership_application_id]
  )
  output_schema(
    type: "object",
    properties: {
      application: Mcp::MembershipApplicationRecords::SCHEMA,
      checklist: { type: %w[object null], properties: { id: { type: "string" }, title: { type: "string" } }, required: %w[id title] },
      overall: { anyOf: [ { type: "object", properties: { status: { type: "string" }, text: { type: "string" } }, required: %w[status text] }, { type: "null" } ] },
      counts: { type: %w[string null], description: "\"4 of 6 done\"" },
      waiting_for: { type: "array", items: { type: "string" } },
      approval_waits: { type: "boolean" },
      items: { type: "array", items: ITEM_SCHEMA }
    },
    required: %w[application checklist overall counts waiting_for approval_waits items]
  )

  def call(membership_application_id:)
    application = ctx.find(MembershipApplication, membership_application_id)
    ctx.authorize!(application, :update?)

    status = Intake::ApplicationChecklists.new([ application ], ctx.person).status_for(application)
    return { application: application_json(application), checklist: nil, overall: nil, counts: nil, waiting_for: [], approval_waits: false, items: [] } unless status

    open_items = status.explained.select { |entry| entry.item.counts? && (entry.not_met? || entry.pending?) }
    checklist = application.registration.checklist
    {
      application: application_json(application),
      checklist: { id: checklist.neat_id, title: checklist.title },
      overall: status.overall && { status: status.overall.status, text: status.overall.text },
      counts: Intake::ApplicationChecklists.counts_text(status),
      waiting_for: open_items.map { |entry| entry.item.label },
      approval_waits: application.pending? && application.registration.gate_approval? && !status.overall&.met? && !status.overall&.exempt?,
      items: status.explained.map { |entry| item_json(application, entry) }
    }
  end

  private

  # The partial's line for an item; the owner is the page's own helper.
  def item_json(application, entry)
    {
      label: entry.item.label,
      status: entry.status,
      text: entry.text,
      summary: entry.full? ? entry.summary.presence : nil,
      excused_by: entry.excuse && entry.excuse["by"],
      to_do: ApplicationController.helpers.intake_item_owner(application, entry)
    }
  end
end
