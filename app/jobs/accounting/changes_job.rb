# Copies what changed at a source since the last check (Sync now, and every
# 15 minutes for sources with a change feed).
class Accounting::ChangesJob < Accounting::SyncJob
  private
    def sync(sync)
      sync.source.capabilities.include?(:change_feed) ? sync.changes : sync.full
    end
end
