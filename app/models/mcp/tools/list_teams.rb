# Teams as the teams index lists them (TeamsController#index:
# policy_scope(Team)), including the "All Teams" filter. parent_id narrows to
# the direct children of a team in policy_scope(Team). A team's parent is
# named only when it is in policy_scope(Team) too, else null. The index shows each
# team's descendant headcount to everyone; this returns only direct members
# who are in policy_scope(Person), so a team the viewer can see but isn't in
# (an open team) doesn't reveal its roster size beyond the people they can see.
class Mcp::Tools::ListTeams < Mcp::Tool
  tool_name "list_teams"
  description "Teams you can see, ordered by name, with their type, parent team and number of members you can see. " \
    "Optionally only the direct sub-teams of one team."
  scope :read
  input_schema(
    properties: {
      parent_id: { type: "string", description: "Only the direct sub-teams of this team (tm_ ID)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: "string" },
            team_type: { type: "string" },
            parent: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
            member_count: { type: "integer" }
          },
          required: %w[id name team_type parent member_count]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(parent_id: nil, limit: DEFAULT_LIMIT)
    teams = ctx.policy_scope(Team)
    teams = teams.where(parent_id: ctx.find(teams, parent_id).id) if parent_id

    result = list(teams.includes(:team_type, :parent).order(:name, :id), limit: limit) { |team| team }
    counts = Membership.where(team_id: result[:items].map(&:id), person_id: ctx.policy_scope(Person).select(:id)).group(:team_id).count

    visible_parents = ctx.policy_scope(Team).where(id: result[:items].filter_map(&:parent_id)).pluck(:id)

    result.merge(items: result[:items].map do |team|
      parent = team.parent if visible_parents.include?(team.parent_id)
      team_json(team).merge(team_type: team.team_type.name, parent: parent && team_json(parent), member_count: counts[team.id] || 0)
    end)
  end
end
