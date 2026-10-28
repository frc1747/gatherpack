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
  # architects, or whoever signs in as it could use their powers. Otherwise
  # only the person themselves or an admin changes a login: a manager who
  # could set someone's email or password could sign in as them.
  def update?
    return false if record&.architect? && !user&.architect?
    record == user || user.admin?
  end

  def destroy?
    user.admin?
  end
end
