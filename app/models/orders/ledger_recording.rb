# Where orders meets the upstream Ledger and Budgets features (spec §6).
# Both can be turned off; everything ledger- or budget-related in orders
# asks here first, so orders works the same with them off.
module Orders
  module LedgerRecording
    module_function

    def ledger_on?
      GatherPack::Features.enabled?(:ledger)
    end

    def budgets_on?
      GatherPack::Features.enabled?(:budgets)
    end

    # The ledgers a person may add entries to (LedgerEntryPolicy#create?),
    # by name. None while the ledger is off.
    def ledgers_for(person)
      return [] unless ledger_on? && person&.user

      Ledger.includes(:team).order(:name).select { |ledger| can_add_to?(person, ledger) }
    end

    def can_add_to?(person, ledger)
      return false unless ledger_on? && person&.user && ledger

      LedgerEntryPolicy.new(person.user, LedgerEntry.new(ledger: ledger)).create?
    end

    # The ledger tags an entry for this funding source carries: those of its
    # linked Budget, so the entry counts against that Budget. None while
    # Budgets is off.
    def tags_for(funding_source)
      return [] unless budgets_on? && funding_source&.budget

      funding_source.budget.ledger_tags.to_a
    end
  end
end
