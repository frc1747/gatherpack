# One team, as TeamsController#show renders it. TeamPolicy has no show?, so
# (like the controller's set_team) the team must be in policy_scope(Team);
# otherwise it is "Not found". The page picks the full or the public view with
# show_full?; both show the description and managers, which is what this
# returns. The full view's extras (announcements, calendar, sibling teams, edit
# controls) are not returned. The parent and sub-teams are returned only where
# they are in policy_scope(Team) (the full view shows the parent and all
# sub-teams; the public view shows neither). Members are the direct members
# who are in policy_scope(Person), with the manager flag, at most `limit`, and
# only where the page would show the roster: TeamsController#show renders
# show_public unless policy(team).show_full?, and show_public lists managers
# but not members. Every direct member has show_full?, so without it the list
# is empty. membership_id is what remove_team_member takes; it's null unless the viewer may remove that membership (the tool's own destroy? check).
class Mcp::Tools::GetTeam < Mcp::Tool
  tool_name "get_team"
  description "A team you can see: description, type, parent team, sub-teams, managers and the members you can see " \
    "(with whether they manage the team, and the membership ID if you may remove them), ordered by last name. " \
    "As on the team page, the member list is only for admins, architects, members and managers of the team (or a parent team); " \
    "anyone else sees the managers and no members."
  scope :read
  input_schema(
    properties: { team_id: { type: "string", description: "Team ID (tm_...)" }, limit: limit_property },
    required: [ "team_id" ]
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      description: { type: %w[string null] },
      team_type: { type: "string" },
      parent: { anyOf: [ REF_SCHEMA, { type: "null" } ] },
      children: { type: "array", items: REF_SCHEMA },
      managers: { type: "array", items: REF_SCHEMA },
      members: { type: "array", items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" }, manager: { type: "boolean" }, membership_id: { type: %w[string null] } }, required: %w[id name manager membership_id] } },
      truncated: { type: "boolean" }
    },
    required: %w[id name description team_type parent children managers members truncated]
  )

  def call(team_id:, limit: DEFAULT_LIMIT)
    team = ctx.find(Team, team_id)
    members = team.memberships.where(person_id: ctx.policy_scope(Person).select(:id)).joins(:person).includes(:person)
    members = members.none unless ctx.allowed?(team, :show_full?)
    members = members.order("people.last_name", "people.first_name", "memberships.id")
    listed = list(members, limit: limit) do |membership|
      person_json(membership.person).merge(manager: membership.manager == true,
        membership_id: ctx.allowed?(membership, :destroy?) ? membership.neat_id : nil)
    end
    parent = team.parent if team.parent_id && ctx.policy_scope(Team).exists?(team.parent_id)

    team_json(team).merge(
      description: team.description,
      team_type: team.team_type.name,
      parent: parent && team_json(parent),
      children: ctx.policy_scope(team.children).order(:name, :id).map { |child| team_json(child) },
      managers: team.managers.order(:last_name, :first_name, :id).map { |person| person_json(person) },
      members: listed[:items],
      truncated: listed[:truncated]
    )
  end
end
