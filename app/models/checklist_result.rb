# A stored answer for one person on one item, or on the checklist overall
# (item_id nil). A cache: any row can be deleted and recomputed by
# Checklists::Refresher. Its status change fires the hook event
# "checklist_results - status changed" from the refresh job, with
# previous_status set.
class ChecklistResult < ApplicationRecord
  has_neat_id :chlres

  belongs_to :checklist
  belongs_to :item, class_name: "ChecklistItem", optional: true
  belongs_to :person

  # No generated scopes: Rails' negative scope for met (not_met) would clash
  # with the not_met value's own. Filter with where(status: ...) instead.
  enum :status, { met: 0, pending: 1, not_met: 2, exempt: 3 }, scopes: false
  enum :previous_status, { met: 0, pending: 1, not_met: 2, exempt: 3 }, prefix: :previously, scopes: false

  def identifier_name
    "#{checklist&.title}: #{item&.label || "Overall"} for #{person&.display_name}"
  end

  def identifier_icon
    "list-check"
  end

  def overall?
    item_id.nil?
  end
end
