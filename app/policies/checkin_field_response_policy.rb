class CheckinFieldResponsePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(team: person.all_teams).or(scope.where(team_id: ""))
      end
    end
  end

  # Responses are changed through their check-in (CheckinPolicy); these are
  # asked only when an admin reverts a response from the audit log.
  def create?
    user.admin?
  end

  def update?
    user.admin?
  end
end
