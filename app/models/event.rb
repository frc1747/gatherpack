class Event < ApplicationRecord
  has_neat_id :evt
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :event_type
  belongs_to :team, optional: true
  belongs_to :time_clock_period, optional: true

  has_many :checkins
  has_many :checkin_field_responses, through: :checkins

  # all_day and tba events hold the whole of their day in start_time and end_time.
  enum :time_kind, { timed: "timed", all_day: "all_day", tba: "tba" }, validate: true

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
    return if timed?

    day = @event_date || start_time&.in_time_zone&.to_date
    return if day.nil?

    self.start_time = day.in_time_zone.beginning_of_day
    self.end_time = day.in_time_zone.end_of_day
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
    checkins.each do |checkin|
      checkin.refresh_fields
    end if event_type_id_changed?
  end
end
