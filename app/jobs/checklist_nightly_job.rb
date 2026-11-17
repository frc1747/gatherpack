# Nightly: date housekeeping (Checklists::Housekeeping), then a full
# recomputation of every draft and active checklist, which repairs anything
# a change or the clock missed.
class ChecklistNightlyJob < ApplicationJob
  queue_as :default

  def perform
    return unless Checklists.enabled?

    Checklists::Housekeeping.run
    Checklist.refreshable.find_each do |checklist|
      Checklists::Refresher.new(checklist).call
    rescue StandardError => e
      Rails.logger.error("Nightly refresh of checklist #{checklist.id} failed: #{e.class}: #{e.message}")
    end
  end
end
