class Checkin < ApplicationRecord
  has_neat_id :cki
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :person
  belongs_to :event
  has_many :checkin_field_responses, dependent: :destroy
  accepts_nested_attributes_for :checkin_field_responses, reject_if: :new_response_on_saved_checkin?

  validates :person, presence: true, uniqueness: { scope: :event, message: "has already been checked in" }
  validate :check_limit

  before_validation :keep_response_fields
  before_validation :drop_other_types_new_responses, on: :create
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
    event.event_type.checkin_fields.reject(&:linked?).each do |field|
      unless checkin_field_responses.any? { |r| r.checkin_field_id == field.id }
        response = checkin_field_responses.build(checkin: self, checkin_field: field)
        response.save unless self.new_record?
      end
    end
  end

  # Responses for the event type's current fields. Answers for another type's
  # fields are kept, hidden, so changing the type back restores them.
  def current_field_responses
    field_ids = event.event_type.checkin_fields.map(&:id)
    checkin_field_responses.select { |r| field_ids.include?(r.checkin_field_id) }
  end

  private

  # A saved response stays with its field, so nested attributes can't move an
  # answer onto or off a field the acting person may not write. Answers for
  # another type's fields are hidden, so they can't be edited at all. This runs
  # before refresh_fields, which would otherwise fill the gap left behind.
  def keep_response_fields
    field_ids = event.event_type.checkin_fields.map(&:id)
    checkin_field_responses.each do |r|
      next unless r.persisted?

      r.restore_attributes([ :checkin_field_id ])
      r.restore_attributes unless field_ids.include?(r.checkin_field_id)
    end
  end

  # refresh_fields has already added every response a saved check-in needs, so
  # a form never adds one; an id-less row there is forged.
  def new_response_on_saved_checkin?(attributes)
    persisted? && attributes["id"].blank?
  end

  # Responses for another type's fields are only ever kept from earlier answers.
  def drop_other_types_new_responses
    field_ids = event.event_type.checkin_fields.map(&:id)
    other = checkin_field_responses.reject { |r| field_ids.include?(r.checkin_field_id) }
    checkin_field_responses.delete(*other) if other.any?
  end

  def check_limit
    limit = self.event.checkin_limit || 0

    if limit > 0 && self.event.checkins.count >= limit
      errors.add(:base, "Unable to checkin, checkin count exceeds checkin limit for this event.")
    end
  end
end
