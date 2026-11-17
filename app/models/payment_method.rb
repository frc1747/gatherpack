# How a purchase was paid: a team card, someone's own money and so on. A
# managed list (GatherPack::ManagedLists): admins add, rename, reorder and
# retire them. One marked reimburse means the buyer is paid back.
class PaymentMethod < ApplicationRecord
  include ManagedList
  has_neat_id :pmt
  managed_list uses: { purchases: :payment_method_id }

  has_many :purchases, dependent: :restrict_with_error

  def identifier_icon
    "credit-card"
  end

  def identifier_name
    name
  end
end
