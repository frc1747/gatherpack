# Approves or denies an application, as MembershipApplicationsController#update does.
#
# Mirrors: set_membership_application (line 67, authorize update?: admins and the team's
# managers, ancestors' included), update (lines 36-45: approve!, which also creates the
# membership, or deny!). Found through policy_scope(MembershipApplication), so an applicant
# gets "Not allowed" on their own and anyone else "Not found".
#
# Only a pending one, as the page offers (_application line 29, show line 52). The PATCH has
# no such check: approving twice raises there, and denying an approved one would leave the
# membership in place. A validation approve! or deny! raises, which the page shows as a
# crash, comes back as an invalid-argument error with nothing changed. The application's own is
# asked first: approve! creates the membership before it saves the application, and a rollback
# wouldn't take back the membership's audit row or the hooks that ran.
#
# While registration (feature :intake) is on, the page also asks what Intake::ApplicationDecisions
# and Intake::ApplicationGating add, and so does this: nobody decides their own application or a
# relative's (refused, as the page redirects with an alert); an approval from a registration waits for
# its checklist when the registration gates it (the gate's reason); a registration's required
# pick-one team must be chosen (pick_team_id, from its list, which the page's select offers), and
# the approving login is recorded so placement gives only the badges it may give; a denial's
# reason is kept as the reviewer's note and sent to the applicant. The page takes the reason and the
# pick only for an application from a registration, and ignores them otherwise; here they are
# refused then, so a reason isn't dropped with a success. The approval's placement (also-add
# teams, badges, guardians' teams) comes back in the call's records. decide_membership_applications
# does several at once, as the page's bulk bar does.
class Mcp::Tools::DecideMembershipApplication < Mcp::Tool
  include Mcp::MembershipApplicationRecords
  include Mcp::IntakeDecisions

  tool_name "decide_membership_application"
  description "Approve (adding them to the team) or deny a pending application, as Approve and Deny do on the team's applications page. " \
    "An application you can see but not decide is \"Not allowed\". Returns the application."
  scope :write
  input_schema(
    properties: {
      membership_application_id: { type: "string", description: "The application's ID (ma_)" },
      decision: { type: "string", enum: %w[approved denied], description: "approved or denied" },
      reason: { type: "string", description: "With denied, for an application from a registration: why. Kept as the reviewer's note and sent to the applicant." },
      pick_team_id: { type: "string", description: "With approved, for an application from a registration with a pick-one list: the team (tm_) to also add them to. Required when the registration requires one." }
    },
    required: %w[membership_application_id decision]
  )
  output_schema(Mcp::MembershipApplicationRecords::SCHEMA)

  def call(membership_application_id:, decision:, reason: nil, pick_team_id: nil)
    application = ctx.find(MembershipApplication, membership_application_id)
    ctx.authorize!(application, :update?)
    invalid_argument!("This application is already #{application.status}") unless application.pending?
    invalid_argument!(OWN_MESSAGE) if own_or_relative?(application)

    invalid_argument!(application.errors.full_messages.to_sentence) unless application.valid?

    reason = reason.strip.presence if reason
    prepare_intake(application, decision, reason, pick_team_id)
    decide(application, decision, reason)
    application_json(application)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  # The page's checks before a decision on an application from a registration, while the
  # feature is on. The pick and the reason are refused where the page would ignore them.
  def prepare_intake(application, decision, reason, pick_team_id)
    applies = application.registration && Intake.enabled?
    invalid_argument!("A reason is kept only for a denied application from a registration") if reason.present? && !(applies && decision == "denied")
    invalid_argument!("pick_team_id is for approving an application from a registration") if pick_team_id.present? && !(applies && decision == "approved")
    return unless applies && decision == "approved"

    invalid_argument!(gate_reason(application)) if gate_reason(application)
    pick = pick_team_id.present? ? (Mcp.find_by_neat_id(application.registration.pick_one_teams, pick_team_id) || invalid_argument!("Not one of this registration's teams to pick from")) : nil
    invalid_argument!("Choose a team for #{application.person.first_name}.") if pick.nil? && Intake::Placement.new(application: application).pick_required?
    application.intake_pick_team = pick
    application.intake_approver = ctx.user
  end

  def decide(application, decision, reason)
    if decision == "approved"
      before = placement_records(application)
      application.approve!
      membership = Membership.find_by!(person: application.person, team: application.team)
      changed!(application, membership, *(placement_records(application) - before - [ membership ]))
    else
      application.deny!(reason.presence)
      changed!(application)
    end
  end
end
