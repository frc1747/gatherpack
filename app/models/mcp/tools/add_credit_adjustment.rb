# Gives or takes credit for a person on a count item, as the item's "Give or take credit"
# does (CommitmentAdjustmentsController#create on the count item's commitment).
#
# Mirrors: the checklist is found as the checklists page finds it (policy_scope(Checklist)) and
# the item in it (checklist.checklist_items); only a count item has credit. Then create (build
# through the commitment with credits and reason, created_by the viewer's person; authorize
# create?, then the person, one of the commitment's owing_people, otherwise nil). The policy,
# CommitmentAdjustmentPolicy#create?, is the item's organizers (CommitmentPolicy#manage?, which
# a count item answers from the checklist: Checklist#organizer?) unless the person is the
# organizer, a relative, or in a group with either (Commitment#self_or_relative_in_group?):
# "Another organizer needs to adjust your own family's credit", named in the refusal as the page
# names it. Credit pools, so an adjustment counts for the person's whole group. The model's
# validations (credits a whole number other than 0, a reason) come back as invalid-argument
# errors. The page doesn't stop an archived checklist's adjustment, so neither does this.
#
# A person who doesn't owe the item is the form's empty choice, which saves nothing, so it's
# "Not found". It isn't looked up until the viewer is known to run the item, so a member can't
# learn who owes it. credits must be a JSON integer that fits the column; the page would raise
# on one that doesn't. The reason is a note about a member: masked in the call log. Needs the
# checklists feature (which turns on the commitments the page checks).
class Mcp::Tools::AddCreditAdjustment < Mcp::Tool
  include Mcp::ChecklistRecords

  INTEGER_RANGE = (-2_147_483_648..2_147_483_647)

  tool_name "add_credit_adjustment"
  description "Give or take credit (negative credits) for a person on a count item, with a reason, as the item's Give or take credit does. " \
    "Credit pools: it counts for the person's whole group. Only the checklist's organizers, and not for themselves, their relatives or anyone " \
    "in a group with either: that is \"Not allowed\". A checklist you can't see, or a person who doesn't owe the item, is \"Not found\". " \
    "Returns the person's numbers on the item."
  scope :write
  feature :checklists
  mask_argument :reason
  input_schema(
    properties: {
      checklist_id: { type: "string", description: "The checklist's ID (chkl_)" },
      item_id: { type: "string", description: "A count item on it (chli_)" },
      person_id: { type: "string", description: "A person who owes the item (per_)" },
      credits: { type: "integer", minimum: INTEGER_RANGE.min, maximum: INTEGER_RANGE.max, description: "A whole number other than 0; negative takes credit away" },
      reason: { type: "string", description: "Why; shown to the item's organizers" }
    },
    required: %w[checklist_id item_id person_id credits reason],
    closed: true
  )
  output_schema(Mcp::ChecklistRecords::COUNT_SCHEMA.then do |schema|
    schema.merge(properties: schema[:properties].merge(adjustment_id: { type: "string" }), required: schema[:required] + %w[adjustment_id])
  end)

  def call(checklist_id:, item_id:, person_id:, credits:, reason:)
    checklist = find_checklist(checklist_id)
    item = find_item(checklist, item_id)
    commitment = (item.commitment if item.count?) || not_found!
    adjustment = commitment.commitment_adjustments.build(credits: credits, reason: reason, created_by: ctx.person)
    ctx.authorize!(adjustment, :create?)

    person = Mcp.find_by_neat_id(Person, person_id)
    not_found! unless person && commitment.owing_people.exists?(id: person.id)
    adjustment.person = person
    refuse_self_approval!(commitment, person) unless ctx.allowed?(adjustment, :create?)

    invalid_argument!(adjustment.errors.full_messages.to_sentence) unless adjustment.save

    changed!(adjustment)
    count_json(item, commitment, person).merge(adjustment_id: adjustment.neat_id, credits: adjustment.credits)
  end

  private

  def refuse_self_approval!(commitment, person)
    refuse!((commitment.self_approval_reason(ctx.person, person) if ctx.allowed?(commitment, :manage?)))
  end
end
