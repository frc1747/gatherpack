# Sets or clears a member's manager flag, as MembershipsController#update does.
#
# Mirrors: set_team_or_person (lines 99-100: the team in policy_scope(Team), or the person in
# policy_scope(Person), depending on the route), set_membership (line 104, authorize update?),
# update (line 69). MembershipPolicy#update? is admins and the team's managers, ancestors'
# managers included. Of membership_params (line 109) only manager is taken: no page moves a
# membership to another person or team. Nothing protects a manager's own flag on the page, so
# nothing does here.
class Mcp::Tools::UpdateTeamMember < Mcp::Tool
  tool_name "update_team_member"
  description "Make a team member a manager or stop them being one, as the team's Members page does. " \
    "A membership you can see but not change is \"Not allowed\". Returns the membership."
  scope :write
  input_schema(
    properties: {
      membership_id: { type: "string", description: "The membership's ID (mbr_)" },
      manager: { type: "boolean", description: "Whether they manage the team" }
    },
    required: %w[membership_id manager]
  )
  output_schema(
    type: "object",
    properties: { id: { type: "string" }, person: REF_SCHEMA, team: REF_SCHEMA, manager: { type: "boolean" } },
    required: %w[id person team manager]
  )

  def call(membership_id:, manager:)
    reachable = Membership.where(team_id: ctx.policy_scope(Team).select(:id))
      .or(Membership.where(person_id: ctx.policy_scope(Person).select(:id)))
    membership = ctx.find(reachable, membership_id)
    ctx.authorize!(membership, :update?)
    invalid_argument!(membership.errors.full_messages.to_sentence) unless membership.update(manager: manager)

    changed!(membership) if membership.saved_changes?
    { id: membership.neat_id, person: person_json(membership.person), team: team_json(membership.team), manager: membership.manager? }
  end
end
