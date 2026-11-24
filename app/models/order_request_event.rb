# One entry in a request's timeline: who did what, on which step or line,
# the fields changed (name => [before, after]) and the comment. Written by
# the domain actions in the same transaction as the change. Entries are
# never edited or deleted, by anyone.
#
# Not a hook target: the order_requests and order_lines events cover the
# same changes.
class OrderRequestEvent < ApplicationRecord
  has_neat_id :orev

  belongs_to :order_request, inverse_of: :events
  belongs_to :order_line, optional: true
  belongs_to :actor, class_name: "Person", optional: true

  ACTIONS = %w[
    submitted edited approved changes_requested declined purchased backordered received problem
    cancelled commented reapproval_needed closed followed unfollowed
  ].freeze

  validates :action, inclusion: { in: ACTIONS }

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Timeline entries can't be deleted" }

  def readonly?
    persisted? || super
  end

  # delete skips callbacks and the readonly check, so refuse it here too.
  def delete
    raise ActiveRecord::ReadOnlyRecord, "Timeline entries can't be deleted"
  end

  def approval?
    action.in?(%w[approved changes_requested declined])
  end

  def step_name
    step_key && (Orders::Config.step(step_key)&.name || step_key.humanize)
  end
end
