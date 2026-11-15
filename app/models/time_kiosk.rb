class TimeKiosk
  include ActiveModel::Model

  PERSON_REF_PURPOSE = :time_kiosk
  PERSON_REF_EXPIRES_IN = 5.minutes

  attr_accessor :tool, :token_value, :time_clock_period_id, :time_clock_punch_id
  attr_writer :person_ref

  def token
    @token ||= Token.find_by(value: token_value)
  end

  def time_clock_period
    @time_clock_period ||= TimeClockPeriod.find_by(id: time_clock_period_id)
  end

  def periods_for_token
    token&.person&.time_clock_periods
  end

  def time_clock_punch
    @time_clock_punch ||= TimeClockPunch.find_by(id: time_clock_punch_id)
  end

  # The person whose card was scanned.
  def person
    @person ||= token&.tokenable.then { |tokenable| tokenable if tokenable.is_a?(Person) }
  end

  # A short-lived reference to the scanned person, carried by the profile's
  # buttons in place of their id.
  def person_ref
    @issued_person_ref ||= person&.signed_id(purpose: PERSON_REF_PURPOSE, expires_in: PERSON_REF_EXPIRES_IN)
  end

  # The person named by the reference a profile button sent back, or nil when
  # it is missing, forged, expired or for another purpose.
  def signed_person
    return if @person_ref.blank?

    @signed_person ||= Person.find_signed(@person_ref, purpose: PERSON_REF_PURPOSE)
  end

  def managed_periods
    @managed_periods ||= periods_managed_by(person)
  end

  def signed_person_managed_periods
    @signed_person_managed_periods ||= periods_managed_by(signed_person)
  end

  private

  def periods_managed_by(manager)
    manager&.all_managed_teams&.map(&:time_clock_periods)&.flatten || []
  end
end
