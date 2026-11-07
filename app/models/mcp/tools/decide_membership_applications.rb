# Approves or denies several pending applications on a team's page, as the bulk bar does
# (Intake::BulkDecisionsController#create, with Intake::ApplicationChecklists preloaded):
# authorize the team's applications? (its managers and admins), then each ticked application
# is decided on its own as decide_membership_application would, and the ones that can't be
# are skipped with why, the others still going ahead. The page skips, by its words:
# an application the person can't decide ("not yours to decide": policy update?), their own
# or a relative's, an approval whose checklist isn't done, and one with a required pick-one team,
# which is made one at a time (decide_membership_application with pick_team_id). Deny keeps
# one reason for all, for any application, as the page does. Others the page leaves out
# silently (not pending, not on this team); here a decided one is skipped as already decided and
# an ID that isn't on the team is "Not found". Only while registration is on, as the page is.
class Mcp::Tools::DecideMembershipApplications < Mcp::Tool
  include Mcp::MembershipApplicationRecords
  include Mcp::IntakeDecisions

  tool_name "decide_membership_applications"
  description "Approve or deny several pending applications on one team, as the Approve and Deny buttons on its applications page do for the ticked rows. " \
    "Each is skipped, with why, if it's not yours to decide, is your own or a relative's, waits for a checklist, or needs a team picked (use decide_membership_application for those). " \
    "Deny gives one reason for all. Use dry_run first to see what would change."
  scope :write
  feature :intake
  bulk
  input_schema(
    properties: {
      team_id: { type: "string", description: "The team's ID (tm_)" },
      membership_application_ids: { type: "array", items: { type: "string" }, minItems: 1, maxItems: BULK_LIMIT, description: "The applications' IDs (ma_)" },
      decision: { type: "string", enum: %w[approved denied], description: "approved or denied" },
      reason: { type: "string", description: "With denied: why. Kept as the reviewer's note and sent to each applicant." },
      dry_run: dry_run_property
    },
    required: %w[team_id membership_application_ids decision],
    closed: true
  )
  output_schema(bulk_output_schema(Mcp::MembershipApplicationRecords::SCHEMA))

  def call(team_id:, membership_application_ids:, decision:, reason: nil, dry_run: false)
    team = ctx.find(Team, team_id)
    ctx.authorize!(team, :applications?)
    invalid_argument!("A reason is for denied") if reason.present? && decision != "denied"

    applications = membership_application_ids.uniq.map { |id| Mcp.find_by_neat_id(team.membership_applications, id) || not_found! }
    applications = MembershipApplication.preload_intake_checklist_statuses(MembershipApplication.where(id: applications.map(&:id)).includes(:person, :team, :registration).order(:created_at, :id))
    bulk_write(applications, dry_run: dry_run, json: ->(application) { application_json(application) },
      check: ->(application) { decidable?(application, decision) }) { |application| decide(application, decision, reason&.strip.presence) }
  end

  private

  # The page's reasons, in its order, for what can't be decided here.
  def decidable?(application, decision)
    raise Mcp::InvalidArgument, "Already #{application.status}" unless application.pending?
    raise Mcp::NotAllowed, "Not yours to decide" unless ctx.allowed?(application, :update?)
    raise Mcp::InvalidArgument, "Yours or a relative's" if own_or_relative?(application)

    if decision == "approved"
      raise Mcp::InvalidArgument, "Checklist not done" if gate_reason(application)
      raise Mcp::InvalidArgument, "Choose a team" if pick_required?(application)
    end
    # What approve! or deny! would raise, asked first as the single tool does, so a dry run lists the same rows.
    raise Mcp::InvalidArgument, application.errors.full_messages.to_sentence unless application.valid?

    true
  end

  def pick_required?(application)
    application.registration && Intake::Placement.new(application: application).pick_required?
  end

  def decide(application, decision, reason)
    if decision == "approved"
      before = placement_records(application)
      application.intake_approver = ctx.user if application.registration
      application.approve!
      @changed_records.push(*(placement_records(application) - before))
    else
      application.deny!(reason)
    end
  end
end
