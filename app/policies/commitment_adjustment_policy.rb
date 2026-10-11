# Organizers record adjustments, but nobody adjusts credit for themselves or
# a relative (Commitment#self_or_relative?); another organizer, a team
# manager or an admin has to. #self_approval_reason says why.
class CommitmentAdjustmentPolicy < CommitmentPartPolicy
  def create?
    manage? && !self_or_relative?
  end

  def destroy?
    create?
  end

  def self_approval_reason
    Commitment::SELF_APPROVAL_REASON if self_or_relative?
  end

  private

  def self_or_relative?
    record.person.present? && record.commitment.self_or_relative?(person, record.person)
  end
end
