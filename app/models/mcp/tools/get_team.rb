# One team, as TeamsController#show renders it. TeamPolicy has no show?, so
# (like the controller's set_team) the team must be in policy_scope(Team);
# otherwise it is "Not found". The page picks the full or the public view with
# show_full?; both show the description, managers, parent and sub-teams, which
# is what this returns. The full view's extras (announcements, calendar,
# sibling teams, edit controls) are not returned. Sub-teams are those in
# policy_scope(Team) (the page lists all of them). Members are the direct
# members who are in policy_scope(Person), with the manager flag: the members
# tab lists everyone under the team to any viewer of the team, which an open
# team would turn into a roster of people the viewer can't otherwise see. A
# member of the team can see all its direct members anyway, so for them the
# list is complete.
class Mcp::Tools::GetTeam < Mcp::Tool
  tool_name "get_team"
  description "A team you can see: description, type, parent team, sub-teams, managers and the members you can see " \
    "(with whether they manage the team)."
  scope :read
  input_schema(properties: { team_id: { type: "string", description: "Team ID (tm_...)" } }, required: [ "team_id" ])
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
      members: { type: "array", items: { type: "object", properties: { id: { type: "string" }, name: { type: "string" }, manager: { type: "boolean" } }, required: %w[id name manager] } }
    },
    required: %w[id name description team_type parent children managers members]
  )

  def call(team_id:)
    team = ctx.find(Team, team_id)
    memberships = team.memberships.where(person_id: ctx.policy_scope(Person).select(:id)).includes(:person).sort_by { |membership| [ membership.person.last_name.to_s, membership.person.first_name.to_s, membership.person_id ] }

    team_json(team).merge(
      description: team.description,
      team_type: team.team_type.name,
      parent: team.parent && team_json(team.parent),
      children: ctx.policy_scope(team.children).order(:name, :id).map { |child| team_json(child) },
      managers: team.managers.order(:last_name, :first_name, :id).map { |person| person_json(person) },
      members: memberships.map { |membership| person_json(membership.person).merge(manager: membership.manager == true) }
    )
  end
end
