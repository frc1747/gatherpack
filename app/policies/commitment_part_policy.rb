# The parts of a commitment (sources and organizers) are run by the
# commitment's organizers.
class CommitmentPartPolicy < ApplicationPolicy
  def index?
    manage?
  end

  def show?
    manage?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def manage?
    CommitmentPolicy.new(user, record.commitment).manage?
  end
end
