class TimeClockPeriodPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(team: person.all_teams).or(scope.where(team: nil))
      end
    end
  end

  # The same records Scope lists, which is how the controller loads them.
  def show?
    Scope.new(user, TimeClockPeriod).resolve.exists?(record.id)
  end

  def new?
    person.manager?
  end

  # Only admins may add punches to an "added by admin" period, so only they
  # may set one up or change one.
  def create?
    user.admin? || (manages?(record.team) && !record.added_by_admin?)
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def summary?
    show?
  end
end
