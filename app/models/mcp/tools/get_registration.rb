# A registration's page, as Intake::RegistrationsController#show and its view show it:
# found through policy_scope(Intake::Registration) and authorized show? (the team's managers,
# ancestors' included, and admins), so one you can't run is "Not found". The sign-up lists
# are list_intake_entries and list_waiting_to_finish. Left out on purpose: the bot check's
# keys (settings) and the kiosk's address, which a manager opens from the page.
class Mcp::Tools::GetRegistration < Mcp::Tool
  include Mcp::IntakeRecords

  CHECKLIST_SCHEMA = {
    type: %w[object null],
    properties: {
      id: { type: "string" },
      title: { type: "string" },
      active: { type: "boolean", description: "A draft or archived checklist shows nothing and approval doesn't wait for it" },
      uncovered_teams: { type: "array", items: Mcp::Tool::REF_SCHEMA, description: "Teams people apply to that the checklist doesn't cover" }
    },
    required: %w[id title active uncovered_teams]
  }.freeze

  tool_name "get_registration"
  description "A registration: dates, status, the teams people apply to, what approval also adds, its checklist and how many applications are pending, approved and denied."
  scope :read
  feature :intake
  input_schema(
    properties: { registration_id: { type: "string", description: "The registration's ID (ireg_)" } },
    required: %w[registration_id]
  )
  output_schema(Mcp::IntakeRecords::SCHEMA.merge(
    properties: Mcp::IntakeRecords::SCHEMA[:properties].merge(
      description: { type: %w[string null] },
      slug: { type: "string" },
      join_path: { type: %w[string null], description: "The self-service link's path, when it is on" },
      apply_teams: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      also_add_teams: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      also_give_badges: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      pick_one_teams: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      pick_one_required: { type: "boolean" },
      guardian_also_add_teams: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      gate_approval: { type: "boolean" },
      checklist: CHECKLIST_SCHEMA,
      applications: {
        type: "object",
        properties: { pending: { type: "integer" }, approved: { type: "integer" }, denied: { type: "integer" } },
        required: %w[pending approved denied]
      }
    ),
    required: Mcp::IntakeRecords::SCHEMA[:required] + %w[description slug join_path apply_teams also_add_teams also_give_badges
      pick_one_teams pick_one_required guardian_also_add_teams gate_approval checklist applications]
  ))

  def call(registration_id:)
    registration = ctx.find(Intake::Registration, registration_id)
    ctx.authorize!(registration, :show?)

    registration_json(registration).merge(
      description: registration.description.presence,
      slug: registration.slug,
      join_path: registration.self_service? ? Rails.application.routes.url_helpers.intake_join_path(registration.slug) : nil,
      apply_teams: teams_json(registration.apply_teams),
      also_add_teams: teams_json(registration.also_add_teams),
      also_give_badges: registration.badges.order(:name).map { |badge| { id: badge.neat_id, name: badge.name } },
      pick_one_teams: teams_json(registration.pick_one_teams),
      pick_one_required: registration.pick_one_required?,
      guardian_also_add_teams: teams_json(registration.guardian_also_add_teams),
      gate_approval: registration.gate_approval?,
      checklist: checklist_json(registration),
      applications: counts(registration)
    )
  end

  private

  def teams_json(teams)
    teams.map { |team| team_json(team) }
  end

  # The page shows the checklist only while the checklists feature is on.
  def checklist_json(registration)
    checklist = registration.checklist
    return unless checklist && Checklists.enabled?

    active = registration.active_checklist.present?
    {
      id: checklist.neat_id, title: checklist.title, active: active,
      uncovered_teams: active ? teams_json(registration.checklist_uncovered_teams) : []
    }
  end

  def counts(registration)
    by_status = registration.membership_applications.group(:status).count
    MembershipApplication.statuses.keys.index_with { |status| by_status[status] || by_status[MembershipApplication.statuses[status]] || 0 }
      .slice("pending", "approved", "denied").symbolize_keys
  end
end
