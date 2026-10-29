class TimeKiosk
  include ActiveModel::Model

  # How long the buttons shown after a scan keep working.
  REFERENCE_LIFETIME = 5.minutes

  attr_accessor :tool, :token_value, :time_clock_period_id, :time_clock_punch_id, :person_ref

  def self.verifier
    Rails.application.message_verifier(:time_kiosk)
  end

  def token
    @token ||= Token.find_by_rfid(token_value)
  end

  # The person whose card was scanned. After a scan, the kiosk's buttons name
  # them with a signed, short-lived reference rather than their id, so the
  # kiosk only acts for someone whose card was just scanned there.
  def person
    return @person if defined?(@person)

    id = self.class.verifier.verified(person_ref, purpose: :person) if person_ref.present?
    @person = id && Person.find_by(id: id)
  end

  def person=(person)
    @person = person
  end

  def person_reference
    self.class.verifier.generate(person.id, purpose: :person, expires_in: REFERENCE_LIFETIME)
  end

  def open_punches
    TimeClockPunch.where(person: person, end_time: nil)
  end

  # The periods the person may clock in to: the current ones of their teams,
  # and team-less ones, less those they are already clocked in to.
  def offered_periods
    @offered_periods ||= begin
      periods = TimeClockPeriod.where(team: person.all_teams).or(TimeClockPeriod.where(team: nil)).where("start_time <= ? AND end_time >= ?", Time.current, Time.current)
      periods - open_punches.map(&:time_clock_period).compact.uniq
    end
  end

  def periods_for_token
    token&.person&.time_clock_periods
  end

  def time_clock_period
    @time_clock_period ||= TimeClockPeriod.find_by(id: time_clock_period_id)
  end

  def time_clock_punch
    @time_clock_punch ||= open_punches.find_by(id: time_clock_punch_id)
  end

  def managed_periods
    @managed_periods ||= person&.all_managed_teams&.map(&:time_clock_periods)&.flatten || []
  end
end
