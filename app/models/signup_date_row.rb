# One date on a sheet's Add dates page, or the date, time, name and place
# of an event the sheet made: a date, optional start and end times, a name
# and a location. With no times, the event runs 00:00 to 23:59 until its
# real time is known (spec §3.5); setting it later tells everyone signed up.
# Times are read in Time.zone.
class SignupDateRow
  include ActiveModel::Model
  include ActiveModel::Attributes

  TIME = /\A([01]?\d|2[0-3]):[0-5]\d\z/

  attribute :date, :string
  attribute :start_time, :string
  attribute :end_time, :string
  attribute :name, :string
  attribute :location, :string

  validate :check_date_and_times

  def self.from_event(event)
    start = event.start_time.in_time_zone
    row = new(date: start.to_date.iso8601, name: event.name, location: event.location)
    unless SignupNotices.time_unset?(event.start_time, event.end_time)
      row.start_time = start.strftime("%H:%M")
      row.end_time = event.end_time&.in_time_zone&.strftime("%H:%M")
    end
    row
  end

  # Nothing typed at all, so Add dates skips it.
  def empty?
    [ date, start_time, end_time, name, location ].all?(&:blank?)
  end

  # Attributes for the event, its name defaulting to the given one.
  def event_attributes(default_name = nil)
    day = parsed_date
    starts, ends = start_time.present? ? [ start_time, end_time.presence ] : [ "00:00", "23:59" ]
    {
      name: name.presence || default_name,
      location: location.presence,
      start_time: Time.zone.parse("#{day.iso8601} #{starts}"),
      end_time: ends && Time.zone.parse("#{day.iso8601} #{ends}")
    }
  end

  private

  def parsed_date
    Date.iso8601(date.to_s)
  rescue Date::Error
    nil
  end

  def check_date_and_times
    if date.blank?
      errors.add(:date, "is needed")
    elsif parsed_date.nil?
      errors.add(:date, "isn't a date")
    end
    errors.add(:start_time, "isn't a time") if start_time.present? && !start_time.match?(TIME)
    errors.add(:end_time, "isn't a time") if end_time.present? && !end_time.match?(TIME)
    errors.add(:start_time, "is needed with an end time") if start_time.blank? && end_time.present?
  end
end
