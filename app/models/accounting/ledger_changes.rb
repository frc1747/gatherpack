# Keeps ledger sources current: included into Ledger, LedgerEntry,
# LedgerTagging and LedgerOwnership (config/initializers/accounting.rb),
# it queues Accounting::LedgerSyncJob for the ledger whenever one of them is
# saved or removed and a ledger source covers that ledger's team. Tag and
# ownership changes don't touch their ledger, so polling updated_at would
# miss them. Writes that skip callbacks are caught by the nightly re-read.
# Does nothing while the feature is off.
module Accounting::LedgerChanges
  extend ActiveSupport::Concern

  included do
    after_commit :queue_accounting_ledger_sync
  end

  private
    def queue_accounting_ledger_sync
      return unless Accounting.enabled?
      # Every entry saved touches its ledger; the entry's own callback covers it.
      return if is_a?(Ledger) && !(previously_new_record? || destroyed? || saved_change_to_name? || saved_change_to_team_id?)

      ledger_ids = accounting_ledger_ids
      teams = Ledger.where(id: ledger_ids).pluck(:team_id)
      # A ledger that's gone has no team to check: queued, so its records go too.
      teams = nil if teams.size < ledger_ids.size
      # A ledger moved off a covered team is queued, so its records go.
      teams << attribute_before_last_save("team_id") if teams && is_a?(Ledger)
      Gateway::LedgerSource.queue_sync(ledger_ids, teams&.compact&.uniq)
    end

    # The ledgers this change touches (both, when an entry moved).
    def accounting_ledger_ids
      ids = case self
      when Ledger then [ id ]
      when LedgerTagging then [ LedgerEntry.where(id: ledger_entry_id).pick(:ledger_id) ]
      else [ ledger_id, attribute_before_last_save("ledger_id") ]
      end
      ids.compact.uniq
    end
end
