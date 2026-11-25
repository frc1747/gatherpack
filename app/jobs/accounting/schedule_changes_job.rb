# Every 15 minutes: a ChangesJob for each connected source with a change feed.
class Accounting::ScheduleChangesJob < ApplicationJob
  queue_as :default

  def perform
    return unless Accounting.enabled?

    Accounting.sources.each do |source|
      Accounting::ChangesJob.perform_later(source) if source.syncable? && source.capabilities.include?(:change_feed)
    end
  end
end
