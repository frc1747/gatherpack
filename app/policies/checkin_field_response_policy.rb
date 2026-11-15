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

  # Responses are created along with their check-in; this is asked only when
  # an admin restores a deleted response from the audit log.
  def create?
    user.admin?
  end

  # A response is written by someone its field allows (CheckinField#permission)
  # who may also edit the check-in it belongs to.
  def update?
    record.permission_check(person) && CheckinPolicy.new(user, record.checkin).update?
  end
end
