class LedgerPaymentPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  def create?
    record.ledger.present? && LedgerPolicy.new(user, record.ledger).pay?
  end
end
