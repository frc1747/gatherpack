class LedgerEntryPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.includes(:ledger).where('ledger.team': person.teams).or(scope.includes(:ledger).where('ledger.id': person.ledger_ids))
      end
    end
  end

  # The same records Scope lists, which is how the controller loads them.
  def show?
    Scope.new(user, LedgerEntry).resolve.exists?(record.id)
  end

  def split?
    update?
  end

  def unsplit?
    update?
  end

  def create?
    person.admin? || record.ledger.team.all_managers.include?(person)
  end

  # Changing or deleting one half of a transfer changes the other half too,
  # which is usually in another team's ledger, so the user has to manage the
  # ledgers of every linked entry as well.
  def update?
    person.admin? || [ record, *record.linked_entries ].all? { |entry| entry.ledger.team.all_managers.include?(person) }
  end

  def destroy?
    update?
  end
end
