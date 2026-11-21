# One position at one event: the thing people take. The capacity overrides
# the position's for this event; disabled turns the slot off.
class SignupSlot < ApplicationRecord
  has_neat_id :susl
  include CanBeHooked
  include Signups::SheetChanges
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_position
  belongs_to :event

  # Must run before the dependent destroy below.
  before_destroy :check_no_signups, prepend: true

  # Only cancelled sign-ups are left by the time this runs.
  has_many :signups, dependent: :destroy

  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :event_id, uniqueness: { scope: :signup_position_id }

  delegate :signup_sheet, :people?, :items?, to: :signup_position

  def identifier_name
    "#{signup_position&.name} at #{event&.name}"
  end

  # The cap: this slot's own, or the position's. Nil means no cap.
  def capacity_value
    capacity || signup_position.capacity
  end

  # Places or quantity used by active and fulfilled
  # sign-ups, leaving out one sign-up (the one being changed) if given.
  def used(excluding: nil)
    counted = signups.counted
    counted = counted.where.not(id: excluding.id) if excluding&.persisted?
    items? ? counted.sum(:quantity) : counted.count
  end

  def remaining(excluding: nil)
    cap = capacity_value
    cap && [ cap - used(excluding: excluding), 0 ].max
  end

  def full?
    remaining&.zero? || false
  end


  # For Signups::SheetChanges.
  def changed_signup_sheet_id
    signup_position&.signup_sheet_id
  end
  private

  def check_no_signups
    return unless signups.live.exists?

    errors.add(:base, "#{identifier_name} has sign-ups, so it can't be removed")
    throw :abort
  end
end
