# Withdraws an application, as MembershipApplicationsController#destroy does (line 50):
# set_membership_application (line 67, authorize destroy?: admins, and the applicant while
# it's pending), destroy!. Found through policy_scope(MembershipApplication), so a team's
# manager gets "Not allowed" and anyone else "Not found".
class Mcp::Tools::WithdrawMembershipApplication < Mcp::Tool
  include Mcp::MembershipApplicationRecords

  tool_name "withdraw_membership_application"
  description "Withdraw a team application, as Withdraw does on the applicant's applications page. " \
    "An application you can see but not withdraw is \"Not allowed\". Returns what was removed."
  scope :write
  destructive
  input_schema(
    properties: { membership_application_id: { type: "string", description: "The application's ID (ma_)" } },
    required: %w[membership_application_id]
  )
  output_schema(Mcp::MembershipApplicationRecords::SCHEMA.merge(
    properties: Mcp::MembershipApplicationRecords::SCHEMA[:properties].merge(removed: { type: "boolean" }),
    required: Mcp::MembershipApplicationRecords::SCHEMA[:required] + %w[removed]
  ))

  def call(membership_application_id:)
    application = ctx.find(MembershipApplication, membership_application_id)
    ctx.authorize!(application, :destroy?)
    application.destroy!

    changed!(application)
    application_json(application).merge(removed: true)
  end
end
