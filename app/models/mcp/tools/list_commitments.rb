# Current commitments the viewer can see, as the /commitments page lists them
# (CommitmentsController#index: policy_scope(Commitment)): those they run,
# owe, or whose group they're related to. The spec names
# PersonCommitmentsPolicy#visible_commitments, which covers only what a person
# owes or is related to, so an organizer who doesn't owe would see nothing;
# CommitmentPolicy::Scope is that plus the commitments they run, and is the
# rule the commitment page itself applies. "Current" is a commitment that
# hasn't ended. organizer says whether commitment_progress shows everyone's
# progress (CommitmentPolicy#progress?). Needs the commitments feature.
class Mcp::Tools::ListCommitments < Mcp::Tool
  tool_name "list_commitments"
  description "Current commitments you can see (ones you run, owe, or are related to the people who owe), " \
    "with who owes, the amount and the period, ordered by start date."
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
            owed_each: { type: "integer" },
            unit: { type: "string" },
            starts_on: { type: "string" },
            ends_on: { type: "string" },
            counts_when: { type: "string" },
            organizer: { type: "boolean" }
          },
          required: %w[id title team owing_team owed_each unit starts_on ends_on counts_when organizer]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(limit: DEFAULT_LIMIT)
    commitments = ctx.policy_scope(Commitment).where(ends_on: Date.current..).includes(:team, :owing_team).order(:starts_on, :title, :id)
    list(commitments, limit: limit) do |commitment|
      {
        id: commitment.neat_id,
        title: commitment.title,
        team: team_json(commitment.team),
        owing_team: team_json(commitment.owing_team),
        owed_each: commitment.base_amount,
        unit: commitment.unit,
        starts_on: date_json(commitment.starts_on),
        ends_on: date_json(commitment.ends_on),
        counts_when: commitment.counts_when,
        organizer: ctx.allowed?(commitment, :progress?)
      }
    end
  end
end
