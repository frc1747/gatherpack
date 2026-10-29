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

  # Mirrors Scope: admins, and members of the budget period's team.
  def show?
    user.admin? || (record.budget_period.present? && person.teams.exists?(record.budget_period.team_id))
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

  def destroy?
    update?
  end
end
