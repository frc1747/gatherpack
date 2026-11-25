# Copies one record a source's notification named.
class Accounting::FetchRecordJob < Accounting::SyncJob
  private
    def sync(sync, entity_type, external_id)
      sync.fetch(entity_type, external_id)
    end
end
