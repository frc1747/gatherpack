class MembershipPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(team_id: person.all_team_ids).or(scope.where(person_id: person.id))
      end
    end
  end

  def new?
    user.admin || user.person.manager?
  end

  # Managers add people to their teams. Anyone else may only join an open team
  # themselves, and never as a manager.
  def create?
    return true if user.admin || record.team&.manager?(person)

    record.person == person && !record.manager? && record.team&.has_account?
  end

  # Managers change memberships on the teams they manage, but only their own
  # and those of people they manage, so never an admin's or a superior's.
  def update?
    user.admin || (manages?(record.team) && (record.person == person || manages?(record.person)))
  end
end
