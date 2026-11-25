# A quantity of a line that arrived: who received it, when, and whether it
# came good or with a problem (a DeliveryProblemKind: damaged, the wrong
# item...). Recorded through OrderLine#record_delivery!.
class OrderDelivery < ApplicationRecord
  has_neat_id :ordd
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :order_line
  belongs_to :received_by, class_name: "Person"
  belongs_to :delivery_problem_kind, optional: true
  has_one_attached :photo

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :received_on, presence: true

  after_create_commit { Orders.line_received(self) }

  def good?
    delivery_problem_kind_id.nil?
  end

  def problem?
    !good?
  end

  # "good", or the problem kind's key ("damaged", "wrong_item") or, for a
  # kind admins added, its id: what notifications carry.
  def condition
    return "good" if good?

    delivery_problem_kind&.key || delivery_problem_kind_id
  end

  # What the timeline records: "good", or the kind's id and its name then,
  # so the timeline shows its current name, or that name if it's since
  # been merged away.
  def condition_for_timeline
    good? ? "good" : { "id" => delivery_problem_kind_id, "name" => delivery_problem_kind&.name }
  end

  # How it came, as the page says it: "Good" or the problem kind's name.
  def condition_name
    delivery_problem_kind&.name || "Good"
  end

  def identifier_icon
    "box-open"
  end

  def identifier_name
    "#{quantity} × #{order_line&.display_name}"
  end
end
