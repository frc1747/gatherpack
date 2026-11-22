class LedgerEntryLinkPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    # Mirrors show?: links with at least one entry and none the user can't see.
    # This can be narrower than update?/destroy?: a manager of only a parent
    # team may change its sub-teams' entries but not see them (the entry scope
    # is direct memberships), so they get a 404 here, as they do for the
    # entries themselves in LedgerEntriesController.
    def resolve
      if user.admin
        scope.all
      else
        visible_entries = LedgerEntryPolicy::Scope.new(user, LedgerEntry).resolve
        hidden_link_ids = LedgerEntryLinking.where.not(ledger_entry_id: visible_entries).select(:ledger_entry_link_id)
        scope.where(id: LedgerEntryLinking.select(:ledger_entry_link_id)).where.not(id: hidden_link_ids)
      end
    end
  end

  # A link says which entries make up a transfer, so only someone who may see
  # every one of them may see it.
  def show?
    return true if user.admin?

    entry_ids = record.ledger_entries.ids
    entry_ids.any? && LedgerEntryPolicy::Scope.new(user, LedgerEntry).resolve.where(id: entry_ids).count == entry_ids.size
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
