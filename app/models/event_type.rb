class EventType < ApplicationRecord
  has_neat_id :evtp
  has_paper_trail versions: { class_name: "AuditLog" }
  has_many :events
  has_many :checkin_fields, dependent: :destroy

  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "updated_at" ]
  end

  # Answers held by the type's check-in fields. A type with no events can
  # still have some: answers kept from events that moved to another type.
  def checkin_answer_count
    CheckinFieldResponse.where(checkin_field: checkin_fields).where.not(response: [ nil, "" ]).count
  end
end
