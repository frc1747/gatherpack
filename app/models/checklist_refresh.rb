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
end
