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
class Mcp::Tools::DecideMembershipApplication < Mcp::Tool
  include Mcp::MembershipApplicationRecords

  tool_name "decide_membership_application"
  description "Approve (adding them to the team) or deny a pending application, as Approve and Deny do on the team's applications page. " \
    "An application you can see but not decide is \"Not allowed\". Returns the application."
  scope :write
  input_schema(
    properties: {
      membership_application_id: { type: "string", description: "The application's ID (ma_)" },
      decision: { type: "string", enum: %w[approved denied], description: "approved or denied" }
    },
    required: %w[membership_application_id decision]
  )
  output_schema(Mcp::MembershipApplicationRecords::SCHEMA)

  def call(membership_application_id:, decision:)
    application = ctx.find(MembershipApplication, membership_application_id)
    ctx.authorize!(application, :update?)
    invalid_argument!("This application is already #{application.status}") unless application.pending?

    invalid_argument!(application.errors.full_messages.to_sentence) unless application.valid?

    decide(application, decision)
    application_json(application)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  def decide(application, decision)
    if decision == "approved"
      application.approve!
      changed!(application, Membership.find_by!(person: application.person, team: application.team))
    else
      application.deny!
      changed!(application)
    end
  end
end
