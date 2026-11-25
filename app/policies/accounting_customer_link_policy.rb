# Links decide whose records count for whom: admins only.
class AccountingCustomerLinkPolicy < AdminPolicy
  def confirm_all?
    create?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin ? scope.all : scope.none
    end
  end
end
