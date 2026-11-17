# Current commitments the viewer can see, as the /commitments page lists them
# (CommitmentsController#index: policy_scope(Commitment)): those they run,
# owe, or whose group they're related to. The spec names
# PersonCommitmentsPolicy#visible_commitments, which covers only what a person
# owes or is related to, so an organizer who doesn't owe would see nothing;
# CommitmentPolicy::Scope is that plus the commitments they run, and is the
# rule the commitment page itself applies. "Current" is a commitment that
# hasn't ended. Who owes is stated as the commitment page states it: the owing
# team, narrowed to owing_badge holders, less exempt_badge holders; with
# grouped, base_amount is owed by the group's first member and
# additional_amount by each other. organizer says whether commitment_progress shows everyone's
# progress (CommitmentPolicy#progress?). Needs the commitments feature.
class Mcp::Tools::ListCommitments < Mcp::Tool
  tool_name "list_commitments"
  description "Current commitments you can see (ones you run, owe, or are related to the people who owe), " \
    "with who owes (team, badge limits, grouping), the amounts and the period, ordered by start date. " \
    "Superseded by list_checklists where checklists are on; still works the same."
  scope :read
  feature :commitments
  input_schema(properties: { limit: limit_property })
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            title: { type: "string" },
            team: REF_SCHEMA,
            owing_team: REF_SCHEMA,
            base_amount: { type: "integer" },
            additional_amount: { type: "integer" },
            grouped: { type: "boolean" },
            owing_badge: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            exempt_badge: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            unit: { type: "string" },
            starts_on: { type: "string" },
            ends_on: { type: "string" },
            counts_when: { type: "string" },
            organizer: { type: "boolean" }
          },
          required: %w[id title team owing_team base_amount additional_amount grouped owing_badge exempt_badge unit starts_on ends_on counts_when organizer]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    commitments = ctx.policy_scope(Commitment).where(ends_on: Date.current..).includes(:team, :owing_team, :owing_badge, :exempt_badge).order(:starts_on, :title, :id)
    list(commitments, limit: limit) do |commitment|
      {
        id: commitment.neat_id,
        title: commitment.title,
        team: team_json(commitment.team),
        owing_team: team_json(commitment.owing_team),
        base_amount: commitment.base_amount,
        additional_amount: commitment.additional_amount,
        grouped: commitment.grouped?,
        owing_badge: commitment.owing_badge && { id: commitment.owing_badge.neat_id, name: commitment.owing_badge.name },
        exempt_badge: commitment.exempt_badge && { id: commitment.exempt_badge.neat_id, name: commitment.exempt_badge.name },
        unit: commitment.unit,
        starts_on: date_json(commitment.starts_on),
        ends_on: date_json(commitment.ends_on),
        counts_when: commitment.counts_when,
        organizer: ctx.allowed?(commitment, :progress?)
      }
    end
  end
end
