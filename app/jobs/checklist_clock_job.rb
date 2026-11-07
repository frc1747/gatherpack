# Refreshes checklists whose answers can change with no data change (a
# window edge, a cutoff, a due date, an excuse ending, a kind's own clock)
# once that moment has come, and picks up marks whose refresh job was lost.
# One checklist failing is logged and doesn't stop the others.
class ChecklistClockJob < ApplicationJob
  queue_as :default

  def perform
    return unless Checklists.enabled?

    Checklist.refreshable.where(next_refresh_at: ..Time.current).find_each do |checklist|
      Checklists::Refresher.new(checklist).call
    rescue StandardError => e
      Rails.logger.error("Clock refresh of checklist #{checklist.id} failed: #{e.class}: #{e.message}")
    end

    orphaned = ChecklistRefresh.where(created_at: ...2.minutes.ago).distinct.pluck(:checklist_id)
    orphaned.each do |checklist_id|
      ChecklistRefreshJob.perform_now(checklist_id)
    rescue StandardError => e
      Rails.logger.error("Refresh of checklist #{checklist_id} failed: #{e.class}: #{e.message}")
    end
  end
end
