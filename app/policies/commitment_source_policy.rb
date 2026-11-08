# Organizers add sources whose subject their kind lets them pick (the "who
# may add it" part of a kind). A source whose kind isn't registered can only
# be removed.
class CommitmentSourcePolicy < CommitmentPartPolicy
  def create?
    manage? && subject_allowed?
  end

  def update?
    manage? && record.available? && subject_allowed?
  end

  private

  def subject_allowed?
    kind = record.kind_class
    kind.nil? || record.subject.nil? || kind.subject_allowed?(record.commitment, person, record.subject)
  end
end
