# Reads one ledger again for every ledger source after it changed
# (Accounting::LedgerChanges). One at a time per ledger. Does nothing while
# the feature is off.
class Accounting::LedgerSyncJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(ledger_id) { "accounting-ledger-#{ledger_id}" }

  def perform(ledger_id)
    return unless Accounting.enabled?

    Gateway::LedgerSource.find_each do |source|
      source.sync_ledger(ledger_id)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { gateway_id: source.id, ledger_id: ledger_id })
      source.sync_failed!(e.message)
    end
  end
end
