# Reads one ledger again for a ledger source after it changed
# (Accounting::LedgerChanges). A sync job like the others, so it runs one at
# a time with every other sync of the same source: two ledgers' jobs don't
# race to save the same tag, and a full read can't mark an entry deleted
# that this job just saved.
class Accounting::LedgerSyncJob < Accounting::SyncJob
  private
    def sync(sync, ledger_id)
      sync.source.sync_ledger(ledger_id)
    end
end
