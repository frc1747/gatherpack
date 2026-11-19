# Pending applications the viewer can act on, as MembershipApplicationsController#index
# lists them (lines 8-10): policy_scope(MembershipApplication), which is everything for an
# admin, and otherwise the viewer's own and those for teams they manage. The action calls no
# index?, and every row of the scope passes it. Only pending ones: the page's actions are
# offered on no others (_application line 29). The team filter is the team in
# policy_scope(Team); the page's Team.find (line 57) reaches any team, whose list is then
# empty unless the scope has its applications.
class Mcp::Tools::ListMembershipApplications < Mcp::Tool
  include Mcp::MembershipApplicationRecords

  tool_name "list_membership_applications"
  description "Pending team applications you can act on, newest first: your own, and those for teams you manage. " \
    "Others' applications are left out, so the list may be empty."
  scope :read
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only this team's (tm_)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::MembershipApplicationRecords::SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(team_id: nil, limit: DEFAULT_LIMIT)
    applications = ctx.policy_scope(MembershipApplication).pending
    applications = applications.where(team: ctx.find(Team, team_id)) if team_id

    list(applications.includes(:person, :team).order(created_at: :desc, id: :asc), limit: limit) { |application| application_json(application) }
  end
end
