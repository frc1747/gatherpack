class EventPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(team_id: person.all_teams.map(&:id)).or(scope.where(team_id: nil))
      end
    end
  end

  # The same events Scope lists: an admin sees every event, anyone else the
  # events of their teams and events with no team, which are for everyone.
  def show?
    user.admin? || record.team.nil? || person.all_teams.include?(record.team)
  end

  def new?
    person.all_managed_teams.present? || user.admin
  end

  def create?
    person.all_managed_teams.include?(record.team) || user.admin
  end

  def update?
    person.all_managed_teams.include?(record.team) || user.admin
  end

  def destroy?
    update?
  end

  def arrange?
    update?
  end

  def print?
    update?
  end
end
