# Links decide whose records count for whom: admins, and holders of the
# customer matching badge, who match customers and nothing more.
class AccountingCustomerLinkPolicy < AdminPolicy
  def index?
    matcher?
  end

  def show?
    matcher?
  end

  def create?
    matcher?
  end

  def destroy?
    matcher?
  end

  def confirm_all?
    create?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      Accounting::Access.customer_matcher?(user) ? scope.all : scope.none
    end
  end

  private
    def matcher?
      Accounting::Access.customer_matcher?(user)
    end
end
