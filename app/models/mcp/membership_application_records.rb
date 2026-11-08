# What the membership application tools share: an application as the team's
# applications page shows it (_application and show).
module Mcp::MembershipApplicationRecords
  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      person: Mcp::Tool::REF_SCHEMA,
      team: Mcp::Tool::REF_SCHEMA,
      status: { type: "string" },
      message: { type: %w[string null] },
      applied_at: { type: "string" }
    },
    required: %w[id person team status message applied_at]
  }.freeze

  private

  def application_json(application)
    {
      id: application.neat_id,
      person: person_json(application.person),
      team: team_json(application.team),
      status: application.status,
      message: application.message.presence,
      applied_at: time_json(application.created_at)
    }
  end
end
