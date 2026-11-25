# Every 15 minutes: a ChangesJob for each connected source with a change feed
# that is due for a check (Accounting::ChangeSchedule).
class Accounting::ScheduleChangesJob < ApplicationJob
  queue_as :default

  def perform
    return unless Accounting.enabled?

    Accounting.sources.each do |source|
      next unless source.syncable? && source.capabilities.include?(:change_feed)

      Accounting::ChangesJob.perform_later(source) if Accounting::ChangeSchedule.new(source).due?
    end
  end
end
