# A pin is one person's display state: they see and change only their own.
class MenuPinPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end
  end

  def create?
    own?
  end

  def destroy?
    own?
  end

  private

  def own?
    user.present? && record.user_id == user.id
  end
end
