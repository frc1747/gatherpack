# Billing runs. Admins bill from a rule or from Account Status; holders of
# a rule's badge grant with bill on bill from that rule only
# (Accounting::BillingAccess). The runs list is for admins; a run's page
# is for admins and the person who ran it.
class AccountingBillingRunPolicy < ApplicationPolicy
  def index?
    admin?
  end

  # A new run; record is a run whose rule (if any) says where it starts.
  def create?
    Accounting::BillingAccess.new(user&.person, record.is_a?(AccountingBillingRun) ? record.rule : nil).allowed?
  end

  def new?
    create?
  end

  def show?
    admin? || (record.is_a?(AccountingBillingRun) && record.created_by_id.present? && record.created_by_id == user&.person&.id)
  end

  def export?
    show?
  end

  # Trying failed lines again: whoever may see the run and still may bill.
  def retry_failed?
    show? && create?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user&.admin
      return scope.none unless user&.person

      scope.where(created_by_id: user.person.id)
    end
  end

  private
    def admin?
      user&.admin == true
    end
end
