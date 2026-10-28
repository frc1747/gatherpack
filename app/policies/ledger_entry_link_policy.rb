class LedgerEntryLinkPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      # TODO: This is not great but also you're never going to get a list of these anywhere and doing this would be really complicated...
      scope.all
    end
  end

  # A link is what makes a change to one half of a transfer reach the other
  # half, so only someone who may change every linked entry may touch it.
  def create?
    user.admin? || (record.ledger_entries.any? && record.ledger_entries.all? { |entry| LedgerEntryPolicy.new(user, entry).update? })
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
