# What approving and denying share while registration (feature :intake) is on, the rules
# Intake::ApplicationDecisions and Intake::ApplicationGating add to the applications page and
# Intake::BulkDecisionsController applies to its rows: nobody decides their own application
# or a relative's, a checklist the registration waits for must be done, and an approval
# can add people to teams and badges, which the call's records should list.
module Mcp::IntakeDecisions
  OWN_MESSAGE = "You can't decide your own application or a relative's.".freeze

  private

  def own_or_relative?(application)
    Intake.enabled? && Intake.own_or_relatives?(ctx.person, application.person)
  end

  # Why the registration's checklist holds the approval back, or nil.
  def gate_reason(application)
    application.registration && Intake::ApprovalGate.new(application).reason
  end

  # The memberships and badges an approval can add: the person's, and their guardians' (the
  # guardian list), to compare before and after. Empty without a registration.
  def placement_records(application)
    return [] unless application.registration && Intake.enabled?

    people = [ application.person, *application.person.guardians ]
    Membership.where(person: people).to_a + BadgeAssignment.where(person: application.person).to_a
  end
end
