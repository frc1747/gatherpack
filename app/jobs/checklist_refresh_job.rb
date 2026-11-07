# Recomputes the people marked on one checklist (Checklists.mark), queued
# 30 seconds after the first mark so a burst of changes is one run.
class ChecklistRefreshJob < ApplicationJob
  queue_as :default

  def perform(checklist_id)
    return unless Checklists.enabled?

    checklist = Checklist.find_by(id: checklist_id)
    marked = ChecklistRefresh.take(checklist_id)
    return if checklist.nil? || marked.nil?

    Checklists::Refresher.new(checklist).call(marked == :all ? nil : marked)
  end
end
