# Removes a credit adjustment from a count item, as CommitmentAdjustmentsController#destroy does
# (the "Remove" in the item's list of adjustments).
#
# Mirrors: the checklist is found as the checklists page finds it (policy_scope(Checklist)), the
# item in it, and the adjustment within the item's commitment (destroy: authorize destroy?,
# destroy!). The policy, CommitmentAdjustmentPolicy#destroy?, is create?: the item's organizers,
# but not for their own family's credit (self-approval), named in the refusal as the page names
# it. Returns the person's numbers on the item, as add_credit_adjustment does. Needs the
# checklists feature.
class Mcp::Tools::RemoveCreditAdjustment < Mcp::Tool
  include Mcp::ChecklistRecords

  tool_name "remove_credit_adjustment"
  description "Remove a credit adjustment from a count item, as Remove in the item's list of adjustments does. " \
    "Only the checklist's organizers, and not for their own family's credit: that is \"Not allowed\"; a checklist or adjustment you can't see is \"Not found\". " \
    "Returns the person's numbers on the item."
  scope :write
  feature :checklists
  destructive
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      item_id: { type: "string", description: "The count item (chli_)" },
      adjustment_id: { type: "string", description: "The adjustment's ID (cmad_)" }
    },
    required: %w[checklist_id item_id adjustment_id],
    closed: true
  )
  output_schema(Mcp::ChecklistRecords::COUNT_SCHEMA.then do |schema|
    schema.merge(properties: schema[:properties].merge(removed_adjustment_id: { type: "string" }), required: schema[:required] + %w[removed_adjustment_id])
  end)

  def call(checklist_id:, item_id:, adjustment_id:)
    checklist = find_checklist(checklist_id)
    item = find_item(checklist, item_id)
    commitment = (item.commitment if item.count?) || not_found!
    adjustment = Mcp.find_by_neat_id(commitment.commitment_adjustments, adjustment_id) || not_found!
    # The policy reads the adjustment's commitment, which would otherwise be loaded again.
    adjustment.association(:commitment).target = commitment
    unless ctx.allowed?(adjustment, :destroy?)
      refuse!((commitment.self_approval_reason(ctx.person, adjustment.person) if ctx.allowed?(commitment, :manage?)))
    end

    adjustment.destroy!

    changed!(adjustment)
    count_json(item, commitment, adjustment.person).merge(removed_adjustment_id: adjustment.neat_id, credits: adjustment.credits)
  end
end
