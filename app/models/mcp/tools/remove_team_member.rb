# Removes a person from a team, as MembershipsController#destroy does.
#
# Mirrors: set_team_or_person (lines 99-100: the team in policy_scope(Team), or the person
# in policy_scope(Person), depending on the route), set_membership (line 104, authorize
# destroy?), destroy (line 88, destroy!). MembershipPolicy doesn't define destroy?, so it's
# ApplicationPolicy's, which calls MembershipPolicy#update?: admins and the team's managers.
# A plain member can't remove themselves, on the page or here. Nothing protects a manager's
# own last membership on the page, so nothing does here.
class Mcp::Tools::RemoveTeamMember < Mcp::Tool
  tool_name "remove_team_member"
  description "Remove a person from a team, by the membership's ID. Team managers and admins only. Returns what was removed."
  scope :write
  destructive
  input_schema(
    properties: { membership_id: { type: "string", description: "The membership's ID (mbr_)" } },
    required: [ "membership_id" ]
  )
  output_schema(
    type: "object",
    properties: { id: { type: "string" }, person: REF_SCHEMA, team: REF_SCHEMA, removed: { type: "boolean" } },
    required: %w[id person team removed]
  )

  def call(membership_id:)
    reachable = Membership.where(team_id: ctx.policy_scope(Team).select(:id))
      .or(Membership.where(person_id: ctx.policy_scope(Person).select(:id)))
    membership = ctx.find(reachable, membership_id)
    ctx.authorize!(membership, :destroy?)
    membership.destroy!

    changed!(membership)
    { id: membership.neat_id, person: person_json(membership.person), team: team_json(membership.team), removed: true }
  end
end
