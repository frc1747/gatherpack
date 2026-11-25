# Badge grants widen who can see responses: admins only.
class FormBadgeGrantPolicy < ApplicationPolicy
  def create?
    user.admin
  end

  def destroy?
    user.admin
  end
end
