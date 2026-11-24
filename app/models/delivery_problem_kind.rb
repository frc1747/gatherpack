# What can be wrong with a delivery: damaged, the wrong item and so on. A
# managed list (GatherPack::ManagedLists). A delivery with no kind arrived
# good; one with a kind is a problem for the buyer to settle.
class DeliveryProblemKind < ApplicationRecord
  include ManagedList
  has_neat_id :dpk
  managed_list uses: { order_deliveries: :delivery_problem_kind_id }

  has_many :order_deliveries, dependent: :restrict_with_error

  # The row for a built-in kind ("damaged", "wrong_item"), made from the
  # defaults if it isn't there yet.
  def self.for_key!(key)
    find_by(key: key.to_s) || begin
      Orders::Lists.seed_delivery_problem_kinds!
      find_by!(key: key.to_s)
    end
  end

  def identifier_icon
    "triangle-exclamation"
  end

  def identifier_name
    name
  end
end
