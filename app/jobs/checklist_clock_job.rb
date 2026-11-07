# Refreshes checklists whose answers can change with no data change (a
# window edge, a cutoff, a due date, a kind's own clock) once that moment
# has come, and picks up marks whose refresh job was lost.
class ChecklistClockJob < ApplicationJob
  queue_as :default

  def perform
    return unless Checklists.enabled?

    Checklist.refreshable.where(next_refresh_at: ..Time.current).find_each do |checklist|
      Checklists::Refresher.new(checklist).call
    end

    orphaned = ChecklistRefresh.where(created_at: ...2.minutes.ago).distinct.pluck(:checklist_id)
    orphaned.each { |checklist_id| ChecklistRefreshJob.perform_now(checklist_id) }
  end
end
