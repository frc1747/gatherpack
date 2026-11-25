# Brings a ledger source's owner links up to date for the ledgers some
# people own, after their guardianship changed (Accounting::GuardianshipChanges).
# A sync job like the others, so it waits for any sync of the same source.
class Accounting::OwnerLinksJob < Accounting::SyncJob
  private
    def sync(sync, person_ids)
      sync.source.relink_owners(person_ids)
    end
end
