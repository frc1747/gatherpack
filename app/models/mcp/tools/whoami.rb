# The signed-in member: their person, whether they are an admin, the teams
# they belong to directly and the teams they manage directly, the token's
# scopes and whether writes are possible. Always allowed: it shows only the
# user's own memberships, which their own profile shows them.
class Mcp::Tools::Whoami < Mcp::Tool
  tool_name "whoami"
  description "Who you are signed in as: your person, whether you are an admin, the teams you belong to and manage, " \
    "the access this connection was granted, and whether it can make changes."
  scope :read
  input_schema(properties: {})
  output_schema(
    type: "object",
    properties: {
      person: REF_SCHEMA,
      admin: { type: "boolean" },
      teams: { type: "array", items: REF_SCHEMA },
      managed_teams: { type: "array", items: REF_SCHEMA },
      scopes: { type: "array", items: { type: "string" } },
      writes_enabled: { type: "boolean" }
    },
    required: %w[person admin teams managed_teams scopes writes_enabled]
  )

  def call
    person = ctx.person
    {
      person: person_json(person),
      admin: ctx.user.admin? == true,
      teams: person.teams.order(:name, :id).map { |team| team_json(team) },
      managed_teams: Team.where(id: person.memberships.where(manager: true).select(:team_id)).order(:name, :id).map { |team| team_json(team) },
      scopes: ctx.scopes & Mcp::SCOPES,
      writes_enabled: ctx.writes_allowed?
    }
  end
end
