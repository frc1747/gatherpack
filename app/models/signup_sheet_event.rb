# An event on a sheet. Adding one creates a slot for every position at it;
# removing one removes those slots, which isn't allowed while any has
# sign-ups that aren't cancelled. created_by_sheet marks events the sheet
# made itself (Add dates), as opposed to existing events attached to it.
class SignupSheetEvent < ApplicationRecord
  has_neat_id :suev
  include CanBeHooked
  include Signups::SheetChanges
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_sheet
  belongs_to :event

  validates :event_id, uniqueness: { scope: :signup_sheet_id, message: "is already on this sheet" }

  after_create :add_slots
  before_destroy :remove_slots

  def identifier_name
    "#{signup_sheet&.title}: #{event&.name}"
  end

  def slots
    SignupSlot.where(event_id: event_id, signup_position_id: signup_sheet.signup_positions.select(:id))
  end


  # For Signups::SheetChanges.
  def changed_signup_sheet_id
    signup_sheet_id
  end
  private

  def add_slots
    signup_sheet.signup_positions.each { |position| position.add_slots_for!([ event_id ]) }
  end

  def remove_slots
    if Signup.live.where(signup_slot_id: slots.select(:id)).exists?
      errors.add(:base, "#{event.name} has sign-ups, so it can't be removed from the sheet")
      throw :abort
    end

    slots.each(&:destroy!)
  end
end
