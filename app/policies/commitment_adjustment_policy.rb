# Organizers record adjustments, but nobody adjusts credit for themselves, a
# relative, or anyone in a group with either, since credit pools in a group
# (Commitment#self_or_relative_in_group?); another organizer, a team manager
# or an admin has to. #self_approval_reason says why.
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
    record.person.present? && record.commitment.self_or_relative_in_group?(person, record.person)
  end
end
