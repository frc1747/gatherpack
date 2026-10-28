class BudgetPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.includes(:budget_period).where('budget_periods.team': person.teams)
      end
    end
  end

  def new?
    person.manager?
  end

  def create?
    user.admin? || manages?(record.budget_period&.team)
  end

  def update?
    create?
  end
end
