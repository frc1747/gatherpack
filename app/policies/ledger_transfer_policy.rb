class LedgerTransferPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  def new?
    person.manager?
  end

  # Taking money out of a ledger is the same as posting to it, so it needs
  # LedgerPolicy#update? there; the receiving ledger only has to be one the
  # user can see.
  def create?
    return true if user.admin?

    from_ledger = record.from_ledger
    to_ledger = record.to_ledger
    return false if from_ledger.nil? || to_ledger.nil?

    LedgerPolicy.new(user, from_ledger).update? &&
      LedgerPolicy::Scope.new(user, Ledger).resolve.exists?(id: to_ledger.id)
  end
end
