class PushSubscriptionPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end
  end

  def settings?
    user.present?
  end

  def create?
    own?
  end

  # Unknown endpoints are answered from the policy scope, so there's no row to check.
  def sync?
    user.present?
  end

  def destroy?
    own?
  end

  private

  def own?
    record.user_id == user.id
  end
end
