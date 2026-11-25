# Base of the jobs that copy a source's records. One at a time per source,
# whatever the kind.
# Rate limits and outages are retried with backoff; any other failure is
# kept for the source's page and fires "accounting - sync failed", and the
# records already copied stay as they are. Does nothing while the feature
# is off or the source isn't connected.
class Accounting::SyncJob < ApplicationJob
  queue_as :default

  # One group for every kind of sync job (SolidQueue's default group is the
  # job's class), so a source's full read, changes, fetches, ledger re-reads
  # and uploads all wait for each other.
  limits_concurrency to: 1, key: ->(gateway, *) { gateway.id }, group: "accounting-sync"

  discard_on ActiveJob::DeserializationError

  retry_on Accounting::TemporaryFailure, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.sync_failed!(error.message)
  end

  def perform(gateway, *args)
    return unless Accounting.enabled? && gateway.is_a?(Accounting::Provider) && gateway.syncable?

    sync(Accounting::Sync.new(gateway), *args)
  rescue Accounting::ReconnectNeeded
    # The source has recorded it; syncing waits for someone to reconnect.
  rescue Accounting::TemporaryFailure
    raise
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { gateway_id: gateway.id })
    gateway.sync_failed!(e.message)
  end

  private
    def sync(sync, *args)
      raise NotImplementedError
    end
end
