# A quantity of a line that arrived: who received it, when, and in what
# condition. Recorded through OrderLine#record_delivery!.
class OrderDelivery < ApplicationRecord
  has_neat_id :ordd
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :order_line
  belongs_to :received_by, class_name: "Person"
  has_one_attached :photo

  enum :condition, { good: 0, damaged: 1, wrong_item: 2 }

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :received_on, presence: true

  after_create_commit { Orders.line_received(self) }

  def identifier_icon
    "box-open"
  end

  def identifier_name
    "#{quantity} × #{order_line&.display_name}"
  end
end
