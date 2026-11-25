# Nightly: on Sundays, a full read of every connected source, as a backstop
# for anything the change feed and notifications missed.
class Accounting::NightlyJob < ApplicationJob
  queue_as :default

  def perform
    return unless Accounting.enabled?

    if Date.current.sunday?
      Accounting.sources.each { |source| Accounting::FullSyncJob.perform_later(source) if source.syncable? }
    end
  end
end
