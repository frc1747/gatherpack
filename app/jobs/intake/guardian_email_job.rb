# Asks a named guardian to confirm, with a new link made and sent here (the
# job is queued with the guardian row's id, never a token).
class Intake::GuardianEmailJob < ApplicationJob
  queue_as :default

  def perform(row_id)
    row = Intake::HouseholdMember.unconfirmed_guardians.find_by(id: row_id)
    return unless row&.ward
    return if row.facts["manager_confirms"]
    Intake::Notices.confirm_guardian(row, row.issue_token!)
  end
end
