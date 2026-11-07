# A pending refresh for one person on a checklist, or the whole checklist
# (person_id nil). Unique, so a burst of changes queues one row each;
# ChecklistRefreshJob takes them all.
class ChecklistRefresh < ApplicationRecord
  belongs_to :checklist

  # Takes and removes this checklist's pending rows: nil when there are none,
  # :all when the whole checklist is marked, else the person ids.
  def self.take(checklist_id)
    sql = sanitize_sql([ "DELETE FROM checklist_refreshes WHERE checklist_id = ? RETURNING person_id", checklist_id ])
    ids = connection.select_values(sql)
    return if ids.empty?

    ids.include?(nil) ? :all : ids
  end

  # Restores marks taken by take, without queueing a job (the clock job picks
  # up marks left for more than a couple of minutes).
  def self.put_back(checklist_id, marked)
    ids = marked == :all ? [ nil ] : Array(marked)
    insert_all(ids.map { |id| { checklist_id: checklist_id, person_id: id, created_at: Time.current } }, unique_by: %i[checklist_id person_id])
  end
end
