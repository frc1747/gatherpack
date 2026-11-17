# The quantity of an item at a location: a cache of the sum of its
# movements, written by StockMovement in the same transaction. Not a hook
# target: stock_movements - create covers every change.
class StockLevel < ApplicationRecord
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :item
  belongs_to :location

  validates :location_id, uniqueness: { scope: :item_id }

  # The level row for the pair, created if needed, locked for the rest of
  # the transaction (so a count and a used at the same moment both land).
  def self.locked_for(item, location)
    insert_all([ { id: SecureRandom.uuid, item_id: item.id, location_id: location.id, quantity: 0 } ],
      unique_by: %i[item_id location_id])
    lock.find_by!(item_id: item.id, location_id: location.id)
  end
end
