class CheckinField < ApplicationRecord
  has_neat_id :ckf
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :event_type
  belongs_to :person_field, optional: true
  has_many :checkin_field_responses
  enum :permission, added_by_admin: 0, added_by_manager: 1, added_by_team_member: 2, added_by_participant: 3, added_by_user: 4
  # Who can see responses, relative to the person checked in (PersonField's
  # levels). Fields linked to a person field use that field's rules instead.
  enum :read_permission, PersonField::LEVEL_VALUES, prefix: :read, validate: true

  validates :name, presence: true
  validate :person_field_fixed, on: :update

  after_create :create_checkin_field_responses

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "permission", "updated_at" ]
  end

  def identifier_name
    "#{event_type.name} / #{name}"
  end

  # Shows the person's current value for a person field instead of storing
  # its own responses.
  def linked?
    person_field_id.present?
  end

  # The people whose value or response for this field the viewer may see.
  def readable_people_for(viewer)
    return Person.none if viewer.nil?
    return person_field.readable_subjects_for(viewer) if linked?
    return Person.all if viewer.admin? || read_everyone?

    PersonField.level_people(read_permission, viewer)
  end

  def readable_by?(viewer, person)
    return read_everyone? || viewer&.admin? if person.nil? && !linked?
    person.present? && readable_people_for(viewer).where(id: person.id).exists?
  end

  # The value shown for one check-in: the linked person field's value, or the
  # stored response.
  def value_for(checkin)
    linked? ? checkin.person.field_value(person_field) : checkin.checkin_field_responses.detect { |response| response.checkin_field_id == id }&.response
  end

  private

  # Linking later would orphan the responses already collected.
  def person_field_fixed
    errors.add(:person_field, "can't be changed after the field is created") if will_save_change_to_person_field_id?
  end

  def create_checkin_field_responses
    event_type.events.where("start_time > ?", Time.current).each do |event|
      event.checkins.each do |checkin|
        checkin.refresh_fields
      end
    end
  end
end
