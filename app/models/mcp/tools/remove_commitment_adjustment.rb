# Removes a manual commitment adjustment, as CommitmentAdjustmentsController#destroy does.
#
# Mirrors: set_commitment (line 36, Commitment.find, the adjustment's commitment, found
# as the commitment page is, by CommitmentPolicy#show?), destroy (lines 29-30: the
# adjustment within the commitment, authorize destroy?, destroy!). The policy,
# CommitmentAdjustmentPolicy#destroy? (line 10), is create?: the commitment's
# organizers, but not for their own family's credit (self-approval), named in the
# refusal as the page names it.
#
# Returns the person's progress as commitment_progress shows it (no rows if they no
# longer owe the commitment), with the removed adjustment's ID. Needs the commitments
# feature.
class Mcp::Tools::RemoveCommitmentAdjustment < Mcp::Tool
  tool_name "remove_commitment_adjustment"
  description "Remove a manual commitment adjustment, as Remove in the commitment page's progress table does, by the ID commitment_progress shows an organizer. " \
    "Only the commitment's organizers, and not for their own family's credit: that is \"Not allowed\"; one you can't see is \"Not found\". " \
    "Returns the person's progress as commitment_progress shows it."
  scope :write
  feature :commitments
  destructive
  input_schema(
    properties: { adjustment_id: { type: "string", description: "The adjustment's ID (cmad_)" } },
    required: %w[adjustment_id],
    closed: true
  )
  output_schema(Mcp::Tools::CommitmentProgress.output_schema.then do |schema|
    schema.merge(properties: schema[:properties].merge(removed_adjustment_id: { type: "string" }), required: schema[:required] + %w[removed_adjustment_id])
  end)

  def call(adjustment_id:)
    adjustment = Mcp.find_by_neat_id(CommitmentAdjustment, adjustment_id) || not_found!
    commitment = adjustment.commitment
    not_found! unless ctx.allowed?(commitment, :show?)
    refuse_self_approval!(commitment, adjustment) unless ctx.allowed?(adjustment, :destroy?)

    adjustment.destroy!

    changed!(adjustment)
    # A fresh commitment, so its groups are read after the removal.
    Mcp::Tools::CommitmentProgress.new(ctx).result_for(Commitment.find(commitment.id), adjustment.person).merge(removed_adjustment_id: adjustment.neat_id)
  end

  private

  def refuse_self_approval!(commitment, adjustment)
    reason = commitment.self_approval_reason(ctx.person, adjustment.person) if ctx.allowed?(commitment, :manage?)
    raise Mcp::NotAllowed, "Not allowed: #{reason}" if reason
    raise Mcp::NotAllowed
  end
end
