# Nightly: first a full read of every connected source that's due, as a
# backstop for anything the change feed, notifications or ledger
# callbacks missed, then every enabled rule evaluated for everyone
# (milestones pass without any record changing). Most sources are read on
# Sundays, except a source set to be checked only on request; ledger sources every night, since writes that skip callbacks
# (update_column, delete_all) are only caught this way. Uploaded files
# aren't read again.
class Accounting::NightlyJob < ApplicationJob
  queue_as :default

  def perform
    return unless Accounting.enabled?

    Accounting.sources.each do |source|
      next unless source.syncable?
      next if source.capabilities.include?(:change_feed) && Accounting::ChangeSchedule.new(source).manual?

      due = case source.full_sync_cadence
      when :nightly then true
      when :weekly then Date.current.sunday?
      else false
      end
      Accounting::FullSyncJob.perform_later(source) if due
    end
    AccountingRule.enabled.find_each { |rule| Accounting::EvaluateRuleJob.perform_later(rule) }
  end
end
