# One approver's decision on one step of a request. A material change to
# the request sets cleared_at, and the request then needs that step again.
class OrderApproval < ApplicationRecord
  has_neat_id :orda
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :order_request, inverse_of: :order_approvals
  belongs_to :approver, class_name: "Person"

  enum :decision, { approved: 0, changes_requested: 1, declined: 2 }

  validates :step_key, presence: true
  validates :comment, presence: true, unless: :approved?

  scope :standing, -> { where(cleared_at: nil) }

  def identifier_icon
    "stamp"
  end

  def step
    Orders::Config.step(step_key)
  end

  # The step's current name, or its key if the step has since been removed.
  def step_name
    step&.name || step_key.humanize
  end

  def cleared?
    cleared_at.present?
  end
end
