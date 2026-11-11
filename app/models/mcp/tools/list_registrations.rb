# Registrations, as Intake::RegistrationsController#index lists them (line 9): the page
# authorizes the class (index?: admins and managers of any team) and lists
# policy_scope(Intake::Registration), newest opening first, which is every registration for an
# admin and otherwise those whose team the viewer manages (ancestors' included). Archived
# ones (closed longer than the intake_archive_days setting) are left off unless archived: true,
# as the page's "Show archived" does. The team filter is the team in policy_scope(Team); the
# page's Team.find reaches any team, whose list is then empty unless the scope has its
# registrations.
class Mcp::Tools::ListRegistrations < Mcp::Tool
  include Mcp::IntakeRecords

  tool_name "list_registrations"
  description "Registrations you run, newest opening first: those for teams you manage (admins: all). " \
    "Ones closed longer than the archive setting are left out unless archived is true."
  scope :read
  feature :intake
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only this team's (tm_)" },
      archived: { type: "boolean", description: "Include archived ones (default false)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::IntakeRecords::SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(team_id: nil, archived: false, limit: DEFAULT_LIMIT)
    ctx.authorize!(Intake::Registration, :index?)
    registrations = ctx.policy_scope(Intake::Registration)
    registrations = registrations.where(team: ctx.find(Team, team_id)) if team_id
    registrations = registrations.not_archived unless archived

    list(registrations.includes(:team).order(opens_at: :desc, id: :asc), limit: limit) { |registration| registration_json(registration) }
  end
end
