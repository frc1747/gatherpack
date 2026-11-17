# One level of approval an order request needs (spec §3.3), in position
# order. A request needs every active step whose minimum its total meets.
# Approvals are stored by the step's key, which never changes, so renaming a
# step keeps its approvals. Approvers are badge and team rows: a holder of
# the badge approves for that team and the teams below it, or for every team
# when no team is given. Admins and the team's managers always can.
class ApprovalStep < ApplicationRecord
  include ManagedList
  has_neat_id :apst
  # Approvals point at a step by key, not id, so every step has a key and
  # none is ever deleted: retire it instead.
  managed_list

  has_many :approvers, -> { order(:created_at) }, class_name: "ApprovalStepApprover",
    inverse_of: :approval_step, dependent: :delete_all

  accepts_nested_attributes_for :approvers, allow_destroy: true, reject_if: ->(attributes) { attributes[:id].blank? && attributes[:badge_id].blank? }

  monetize :minimum_cents

  validates :minimum_cents, numericality: { greater_than_or_equal_to: 0 }
  before_validation :assign_key, on: :create
  before_validation :drop_repeated_approvers

  # The step requests use when no step is active: admins and team managers
  # approve every request.
  def self.fallback
    new(key: "approval", name: "Approval", minimum_cents: 0)
  end

  # The Orders::Reach of this step's approvers.
  def reach
    @reach ||= Orders::Reach.from_grants(approvers.map { |approver| [ approver.badge, approver.team ] })
  end

  def reload(*)
    @reach = nil
    super
  end

  def identifier_icon
    "stamp"
  end

  def identifier_name
    name
  end

  private

  # The same badge and team twice is one approver.
  def drop_repeated_approvers
    seen = Set.new
    approvers.each do |approver|
      next if approver.marked_for_destruction?

      approver.mark_for_destruction unless seen.add?([ approver.badge_id, approver.team_id ])
    end
  end

  # A key no step has and no approval or timeline entry uses, so a removed
  # step's approvals never pass to a new one.
  def assign_key
    return if key.present? || name.blank?

    base = name.parameterize(separator: "_").presence || "step"
    taken = self.class.pluck(:key) | OrderApproval.distinct.pluck(:step_key) |
      OrderRequestEvent.where.not(step_key: nil).distinct.pluck(:step_key)
    candidate = base
    number = 1
    candidate = "#{base}_#{number += 1}" while taken.include?(candidate)
    self.key = candidate
  end
end
