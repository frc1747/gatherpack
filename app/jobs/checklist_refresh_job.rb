# Recomputes the people marked on one checklist (Checklists.mark), queued
# 30 seconds after the first mark so a burst of changes is one run. When the
# refresh fails, the marks are put back for the clock job to retry.
class ChecklistRefreshJob < ApplicationJob
  queue_as :default

  def perform(checklist_id)
    return unless Checklists.enabled?

    checklist = Checklist.find_by(id: checklist_id)
    marked = ChecklistRefresh.take(checklist_id)
    return if checklist.nil? || marked.nil?

    begin
      Checklists::Refresher.new(checklist).call(marked == :all ? nil : marked)
    rescue StandardError
      ChecklistRefresh.put_back(checklist_id, marked)
      raise
    end
  end
end
