# The signed-in member: their person, whether they are an admin, the teams
# they belong to directly and the teams they manage directly, the token's
# scopes and whether writes are possible. writes_enabled is the app's setting
# alone and can_write adds this token's scope: a client that connected while writes
# were off holds only mcp_read, so writes_enabled without can_write means it must
# reconnect. Always allowed: it shows only the user's own memberships, which their
# own profile shows them.
class Mcp::Tools::Whoami < Mcp::Tool
  tool_name "whoami"
  description "Who you are signed in as: your person, whether you are an admin, the teams you belong to and manage, " \
    "the access this connection was granted, whether changes are turned on (writes_enabled) and whether this " \
    "connection can make them (can_write). If writes_enabled is true and can_write is false, " \
    "disconnect and reconnect to make changes."
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
      writes_enabled: { type: "boolean" },
      can_write: { type: "boolean" }
    },
    required: %w[person admin teams managed_teams scopes writes_enabled can_write]
  )

  def call
    person = ctx.person
    {
      person: person_json(person),
      admin: ctx.user.admin? == true,
      teams: person.teams.order(:name, :id).map { |team| team_json(team) },
      managed_teams: Team.where(id: person.memberships.where(manager: true).select(:team_id)).order(:name, :id).map { |team| team_json(team) },
      scopes: ctx.scopes & Mcp::SCOPES,
      writes_enabled: Mcp::Access.writes_enabled?,
      can_write: ctx.writes_allowed?
    }
  end
end
