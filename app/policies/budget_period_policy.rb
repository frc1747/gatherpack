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

  # Records are loaded through Scope, which decides who may see them.
  def show?
    true
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

  def destroy?
    update?
  end
end
