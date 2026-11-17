class Event < ApplicationRecord
  has_neat_id :evt
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :event_type
  belongs_to :team, optional: true
  belongs_to :time_clock_period, optional: true

  has_many :checkins, dependent: :destroy
  has_many :checkin_field_responses, through: :checkins
  # Removing an event from its sheets removes its slots, which fails while
  # any has sign-ups that aren't cancelled.
  has_many :signup_sheet_events, dependent: :destroy
  has_many :signup_sheets, through: :signup_sheet_events
  has_many :signup_slots

  # all_day and tba events hold the whole of their day in start_time and end_time.
  enum :time_kind, { timed: "timed", all_day: "all_day", tba: "tba" }, validate: true

  # Events still to come. All-day and TBA events stay until their day ends.
  scope :upcoming, ->(now = Time.current) {
    where("events.start_time >= :now OR (events.time_kind <> 'timed' AND events.end_time >= :now)", now: now)
  }

  validates :name, presence: true
  validates :start_time, presence: true

  before_validation :apply_time_kind
  after_update :update_checkins
  after_save :forget_time_kind_inputs

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "start_time", "end_time", "location", "event_type_id", "team_id", "time_clock_period_id" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "event_type", "team", "time_clock_period" ]
  end

  validate :valid_times
  validate :day_chosen, unless: :timed?

  def time_kind=(value)
    @time_kind_assigned = true
    super
  end

  # The day of an all_day or tba event, as the form sets it.
  def event_date
    @event_date || start_time&.to_date
  end

  def event_date=(value)
    @event_date = ActiveModel::Type::Date.new.cast(value)
  end

  def complete?
    start_time.present? && end_time.present?
  end

  # All-day and TBA events aren't meetings with a known length.
  def hours
    timed? && complete? ? ((self.end_time - self.start_time) / 3600 * 20).round / 20.0 : 0.0
  end

  def identifier_icon
    "calendar"
  end

  def to_combobox_display
    case time_kind
    when "all_day" then "#{name} (#{start_time.strftime("%Y-%m-%d")})"
    when "tba" then "#{name} (#{start_time.strftime("%Y-%m-%d")}, Time TBA)"
    else "#{name} (#{start_time.strftime("%Y-%m-%d %H:%M")})"
    end
  end

  private

  def apply_time_kind
    self.time_kind = "timed" if real_time_saved?

    if timed?
      clear_stored_end
    elsif time_kind_changed? || @event_date || start_time_changed?
      fill_chosen_day
    elsif end_time_changed?
      restore_end_time!
    end
  end

  # The day is worked out in the current zone, so only when something says to
  # move it: a save from a job or console may be in a different zone.
  def fill_chosen_day
    day = @event_date || start_time&.in_time_zone&.to_date
    return if day.nil?

    self.start_time = day.in_time_zone.beginning_of_day
    self.end_time = day.in_time_zone.end_of_day
  end

  # Leaving all_day or tba, the stored end isn't a real one. It may come back
  # from a form at a lower precision, so compare by the second.
  def clear_stored_end
    return unless time_kind_changed? && time_kind_in_database != "timed"

    self.end_time = nil if end_time&.to_i == end_time_in_database&.to_i
  end

  # A new time set without saying what kind it is, as opposed to a form that
  # chose all_day or tba and whose time fields are ignored.
  def real_time_saved?
    !timed? && !@time_kind_assigned && start_time.present? && start_time_changed? &&
      start_time != start_time.in_time_zone.beginning_of_day
  end

  def forget_time_kind_inputs
    @time_kind_assigned = nil
    @event_date = nil
  end

  def day_chosen
    errors.add(:event_date, :blank) if start_time.blank?
  end

  def valid_times
    if start_time? && end_time? then
      errors.add(:end_time, "cannot be before start time!") if end_time.before?(start_time)
    end
  end

  def update_checkins
    return unless saved_change_to_event_type_id?

    field_ids = event_type.checkin_fields.ids
    checkins.each do |checkin|
      # Blank responses for the old type's fields hold no answer and would only
      # block deleting those fields; answered ones are kept (see Checkin).
      checkin.checkin_field_responses.each do |response|
        response.destroy if response.response.blank? && field_ids.exclude?(response.checkin_field_id)
      end
      checkin.checkin_field_responses.reset
      checkin.refresh_fields
    end
    # Don't keep the field list loaded here, so a later check-in on this same
    # event still sees fields added to the type afterwards.
    event_type.checkin_fields.reset
  end
end
