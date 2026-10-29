class Checkin < ApplicationRecord
  has_neat_id :cki
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :person
  belongs_to :event
  has_many :checkin_field_responses, dependent: :destroy
  accepts_nested_attributes_for :checkin_field_responses

  validates :person, presence: true, uniqueness: { scope: :event, message: "has already been checked in" }
  validate :check_limit

  before_validation :keep_response_fields
  before_validation :refresh_fields

  attr_accessor :created_by

  def self.ransackable_attributes(auth_object = nil)
    [ "person.display_name" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "person" ]
  end

  def identifier_name
    "#{person.identifier_name}'s checkin"
  end

  def refresh_fields
    event.event_type.checkin_fields.each do |field|
      unless checkin_field_responses.any? { |r| r.checkin_field_id == field.id }
        response = checkin_field_responses.build(checkin: self, checkin_field: field)
        response.save unless self.new_record?
      end
    end
    checkin_field_responses.each do |response|
      response.delete unless event.event_type.checkin_fields.any? { |f| f.id == response.checkin_field_id }
    end
  end

  private

  # A saved response stays with its field, so nested attributes can't move an
  # answer onto or off a field the acting person may not write. This runs
  # before refresh_fields, which would otherwise fill the gap left behind.
  def keep_response_fields
    checkin_field_responses.each do |r|
      r.restore_attributes([ :checkin_field_id ]) if r.persisted?
    end
  end

  def check_limit
    limit = self.event.checkin_limit || 0

    if limit > 0 && self.event.checkins.count >= limit
      errors.add(:base, "Unable to checkin, checkin count exceeds checkin limit for this event.")
    end
  end
end
