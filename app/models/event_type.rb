class EventType < ApplicationRecord
  has_neat_id :evtp
  has_paper_trail versions: { class_name: "AuditLog" }
  has_many :events
  before_destroy :ensure_no_checkin_field_responses, prepend: true
  has_many :checkin_fields, dependent: :destroy

  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "updated_at" ]
  end

  private

  def ensure_no_checkin_field_responses
    if CheckinFieldResponse.where(checkin_field: checkin_fields).exists?
      errors.add(:base, "Cannot delete an event type whose check-in fields have responses")
      throw :abort
    end
  end
end
