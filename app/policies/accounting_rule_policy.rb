# Account Status: anyone who sees some rule's results opens the list and
# those rules' pages; admins set rules up. A custom rule's code runs with
# full access, so writing it is for architects.
class AccountingRulePolicy < ApplicationPolicy
  def index?
    Accounting::Access.sees_any_rule?(user) || Accounting::Access.customer_matcher?(user)
  end

  def show?
    admin? || Accounting::Access.visible_rules(user).include?(record)
  end

  def export?
    show?
  end

  def create?
    admin?
  end

  def new?
    create?
  end

  def update?
    admin?
  end

  def edit?
    update?
  end

  def destroy?
    admin?
  end

  def evaluate?
    admin?
  end

  def duplicate?
    admin?
  end

  # Giving a person their own milestones, and seeing who has them.
  def payment_plan?
    admin?
  end

  # Setting a custom rule's code, or making a rule custom.
  def write_code?
    admin? && user&.architect == true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin

      scope.where(id: Accounting::Access.visible_rules(user).map(&:id))
    end
  end

  private
    def admin?
      user&.admin == true
    end
end
