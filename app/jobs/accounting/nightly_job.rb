# Nightly: a full read of every connected source as a backstop for
# anything the change feed, notifications or ledger callbacks missed.
# Most sources are read on Sundays; ledger sources every night, since
# writes that skip callbacks (update_column, delete_all) are only caught
# this way. Uploaded files aren't read again.
class Accounting::NightlyJob < ApplicationJob
  queue_as :default

  def perform
    return unless Accounting.enabled?

    Accounting.sources.each do |source|
      next unless source.syncable?

      due = case source.full_sync_cadence
      when :nightly then true
      when :weekly then Date.current.sunday?
      else false
      end
      Accounting::FullSyncJob.perform_later(source) if due
    end
  end
end
