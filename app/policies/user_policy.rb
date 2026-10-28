class UserPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  # Only admins create a login for someone else's person; members get their
  # own by signing up.
  def create?
    user.admin?
  end

  # An architect's login (email, password, flags) is changed only by
  # architects, or whoever signs in as it could use their powers.
  def update?
    return false if record&.architect? && !user&.architect?
    record == user || user.admin? || (person.all_managed_teams & (record&.person&.all_teams || [])).any?
  end

  def destroy?
    user.admin?
  end
end
