# Reads every record of a source again (Copy everything again, the weekly
# backstop, and the first sync after connecting).
class Accounting::FullSyncJob < Accounting::SyncJob
  private
    def sync(sync)
      sync.full
    end
end
