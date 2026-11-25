# Intake's reaction to checklist_status_changed.gatherpack (subscribed in
# config/initializers/intake_checklist.rb): when an applicant's overall on
# their registration's checklist becomes done (Complete, or Not required
# when nothing on it counts for them: Intake::ApprovalGate::DONE), they (or
# their guardians) hear that everything is in and a manager will decide. Approval stays a
# manager's decision; nothing here approves or adds anyone.
module Intake::ChecklistReaction
  module_function

  def call(result, previous_status)
    done = Intake::ApprovalGate::DONE
    return unless Intake.enabled? && result.item_id.nil? && done.include?(result.status) && previous_status.present? && done.exclude?(previous_status)

    applications = MembershipApplication.pending.where(person_id: result.person_id)
      .where(registration_id: Intake::Registration.where(checklist_id: result.checklist_id).select(:id))
      .includes(:team, :person).order(:created_at).to_a
    return if applications.empty?

    Intake::Notices.checklist_done(applications.first.person, applications.map(&:team).uniq)
  end
end
