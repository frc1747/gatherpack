class HookPolicy < AdminPolicy
  # Hooks hold code, so they're listed (in search too) only to admins, who
  # are the only ones who may open them.
  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin? ? scope.all : scope.none
    end
  end

  def create?
    user&.architect?
  end

  def update?
    user&.architect?
  end

  def destroy?
    user&.architect?
  end
end
