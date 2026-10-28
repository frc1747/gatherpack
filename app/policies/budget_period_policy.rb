class BudgetPeriodPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(team: person.teams)
      end
    end
  end

  def new?
    person.manager?
  end

  def create?
    user.admin? || manages?(record.team)
  end

  def update?
    create?
  end
end
