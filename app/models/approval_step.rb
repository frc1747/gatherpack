# One level of approval an order request needs (spec §3.3), in position
# order. Every request needs the first active step, whose minimum is always
# 0; it also needs each later active step whose minimum its total meets.
# Approvals are stored by the step's key, which never changes, so renaming a
# step keeps its approvals. Approvers are grant rows (ApprovalStepApprover):
# holders of a badge, the managers of a team, or the managers of the
# request's own team, for a team and the teams below it or for every team.
# Admins always can; team managers only through a row.
class ApprovalStep < ApplicationRecord
  include ManagedList
  has_neat_id :apst
  # Approvals point at a step by key, not id, so every step has a key and
  # none is ever deleted: retire it instead.
  managed_list

  has_many :approvers, -> { order(:created_at) }, class_name: "ApprovalStepApprover",
    inverse_of: :approval_step, dependent: :delete_all

  accepts_nested_attributes_for :approvers, allow_destroy: true, reject_if: ->(attributes) { ApprovalStepApprover.blank_attributes?(attributes) }

  monetize :minimum_cents

  validates :minimum_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :first_step_has_no_minimum
  before_validation :assign_key, on: :create
  before_validation :drop_repeated_approvers

  # The step requests use when no step is active: admins and the managers
  # of each request's team approve every request.
  def self.fallback
    new(key: "approval", name: "Approval", minimum_cents: 0).tap do |step|
      step.approvers.build(kind: :own_team_managers)
    end
  end

  # The first active step applies to every request, so its minimum is 0.
  # Reordering, retiring or restoring can put a step with a minimum first;
  # this clears that minimum and returns the step, or nil when nothing
  # changed.
  def self.free_first_step!
    first = active.ordered.first
    return nil unless first&.minimum_cents&.positive?

    first.update_column(:minimum_cents, 0)
    first
  end

  # Whether this step is (or, saved, would be) the first active step.
  def first?
    return false unless active?

    others = self.class.active.where.not(id: id).ordered.to_a
    return true if others.empty?
    return false if new_record? && position.nil?

    ([ self ] + others).min_by { |step| [ step.position.to_i, step.name.to_s ] }.equal?(self)
  end

  # The Orders::Reach of this step's approvers.
  def reach
    @reach ||= Orders::Reach.from_rows(approvers.reject(&:marked_for_destruction?).map(&:reach_row))
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

  def first_step_has_no_minimum
    return unless minimum_cents.to_i.positive? && first?

    errors.add(:minimum, "must be $0 for the first step, which every request needs")
  end

  # The same row twice is one approver. Only rows already in memory (the
  # form's), so saving a step alone never loads ApprovalStepApprover: the
  # migrations that make steps run before approver rows had kinds.
  def drop_repeated_approvers
    return if association(:approvers).target.empty?

    seen = Set.new
    approvers.each do |approver|
      next if approver.marked_for_destruction?

      key = [ approver.kind, approver.badge? ? approver.badge_id : nil, approver.team_managers? ? approver.manager_team_id : nil,
        approver.own_team_managers? ? nil : approver.team_id ]
      approver.mark_for_destruction unless seen.add?(key)
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
