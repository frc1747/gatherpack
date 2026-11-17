# Credits (or debits) a person on a commitment by hand, as
# CommitmentAdjustmentsController#create does.
#
# Mirrors: set_commitment (line 36, Commitment.find: unscoped, so the commitment is
# found as the commitment page is, by CommitmentPolicy#show?), create (lines 14-17:
# build through the commitment with adjustment_params, i.e. credits and reason, and
# created_by the viewer's person; the person is owing_person, line 42, one of the
# commitment's owing_people, otherwise nil; authorize create?), then save. The policy,
# CommitmentAdjustmentPolicy#create? (line 6), is the commitment's organizers
# (CommitmentPolicy#manage?) unless the person is the organizer, a relative, or in a
# group with either (Commitment#self_or_relative_in_group?): "Another organizer needs
# to adjust your own family's credit", named in the refusal as the page names it.
# The model's validations (credits a whole number other than 0, a reason) come back
# as invalid-argument errors.
#
# A person who doesn't owe the commitment is the form's empty choice, which saves
# nothing, so it's "Not found". It isn't looked up until the viewer is known to run
# the commitment, so a member can't learn who owes it. There is no "group's owing
# person" to resolve: the page takes the owing person itself, in a group too.
#
# credits must be a JSON integer that fits the column; the page would raise on
# one that doesn't. Needs the commitments feature.
class Mcp::Tools::AddCommitmentAdjustment < Mcp::Tool
  INTEGER_RANGE = (-2_147_483_648..2_147_483_647)

  tool_name "add_commitment_adjustment"
  description "Credit or debit (negative credits) a person who owes a commitment, with a reason, as the commitment page's Adjust does. " \
    "Only the commitment's organizers, and not for themselves, their relatives or anyone in a group with either: that is \"Not allowed\". " \
    "A commitment you can't see, or a person who doesn't owe it, is \"Not found\". Returns the person's progress as commitment_progress shows it. " \
    "Superseded by add_credit_adjustment where checklists are on; still works the same."
  scope :write
  feature :commitments
  # Free text about a member, as a note.
  mask_argument :reason
  input_schema(
    properties: {
      commitment_id: { type: "string", description: "The commitment's ID (cmt_)" },
      person_id: { type: "string", description: "A person who owes the commitment (per_)" },
      credits: { type: "integer", minimum: INTEGER_RANGE.min, maximum: INTEGER_RANGE.max, description: "A whole number other than 0; negative takes credit away" },
      reason: { type: "string", description: "Why; shown on the commitment page" }
    },
    required: %w[commitment_id person_id credits reason],
    closed: true
  )
  output_schema(Mcp::Tools::CommitmentProgress.output_schema.then do |schema|
    schema.merge(properties: schema[:properties].merge(adjustment_id: { type: "string" }), required: schema[:required] + %w[adjustment_id])
  end)

  def call(commitment_id:, person_id:, credits:, reason:)
    commitment = Mcp.find_by_neat_id(Commitment, commitment_id) || not_found!
    not_found! unless ctx.allowed?(commitment, :show?)
    adjustment = commitment.commitment_adjustments.build(credits: credits, reason: reason, created_by: ctx.person)
    ctx.authorize!(adjustment, :create?)

    person = Mcp.find_by_neat_id(Person, person_id)
    not_found! unless person && commitment.owing_people.exists?(id: person.id)
    adjustment.person = person
    refuse_self_approval!(commitment, adjustment) unless ctx.allowed?(adjustment, :create?)

    invalid_argument!(adjustment.errors.full_messages.to_sentence) unless adjustment.save

    changed!(adjustment)
    Mcp::Tools::CommitmentProgress.new(ctx).result_for(commitment, person).merge(adjustment_id: adjustment.neat_id)
  end

  private

  def refuse_self_approval!(commitment, adjustment)
    reason = commitment.self_approval_reason(ctx.person, adjustment.person) if ctx.allowed?(commitment, :manage?)
    raise Mcp::NotAllowed, "Not allowed: #{reason}" if reason
    raise Mcp::NotAllowed
  end
end
