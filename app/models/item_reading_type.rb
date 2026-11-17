# A reading type an item's checks ask for, in the item's order.
class ItemReadingType < ApplicationRecord
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :item
  belongs_to :reading_type

  validates :reading_type_id, uniqueness: { scope: :item_id }
end
