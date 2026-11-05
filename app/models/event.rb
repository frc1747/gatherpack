class Event < ApplicationRecord
  has_neat_id :evt
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :event_type
  belongs_to :team, optional: true
  belongs_to :time_clock_period, optional: true

  has_many :checkins
  has_many :checkin_field_responses, through: :checkins

  validates :name, presence: true
  validates :start_time, presence: true

  after_update :update_checkins

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "start_time", "end_time", "location", "event_type_id", "team_id", "time_clock_period_id" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "event_type", "team", "time_clock_period" ]
  end

  validate :valid_times

  def complete?
    start_time.present? && end_time.present?
  end

  def hours
    complete? ? ((self.end_time - self.start_time) / 3600 * 20).round / 20.0 : 0.0
  end

  def identifier_icon
    "calendar"
  end

  def to_combobox_display
    "#{name} (#{start_time.strftime("%Y-%m-%d %H:%M")})"
  end

  private

  def valid_times
    if start_time? && end_time? then
      errors.add(:end_time, "cannot be before start time!") if end_time.before?(start_time)
    end
  end

  def update_checkins
    return unless saved_change_to_event_type_id?

    field_ids = event_type.checkin_fields.map(&:id)
    checkins.each do |checkin|
      # Blank responses for the old type's fields hold no answer and would only
      # block deleting those fields; answered ones are kept (see Checkin).
      checkin.checkin_field_responses.each do |response|
        response.destroy if response.response.blank? && field_ids.exclude?(response.checkin_field_id)
      end
      checkin.checkin_field_responses.reset
      checkin.refresh_fields
    end
  end
end
