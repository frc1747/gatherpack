# Clocks a scanned person in when they have exactly one choice: unassigned
# punches are turned off and a single period applies to them. Returns a Result
# with the banner to show, or nil when the kiosk should behave as usual.
class TimeKiosk::AutoClockIn
  Result = Struct.new(:period, :punch, :flash_type, :message, keyword_init: true)

  # The periods the person can clock in to: current, and on one of their teams
  # or on no team.
  def self.periods_for(person)
    TimeClockPeriod.where(team: person.all_teams).or(TimeClockPeriod.where(team: nil)).where("start_time <= ? AND end_time >= ?", Time.current, Time.current)
  end

  def self.call(person)
    new(person).call
  end

  def initialize(person)
    @person = person
  end

  def call
    return if TimeKiosk::Config.allow_unassigned?

    periods = self.class.periods_for(@person).to_a
    return result(:warning, "No time period is open for you. See a mentor.") if periods.empty?
    return unless periods.one?

    clock_in(periods.first)
  end

  private

  def clock_in(period)
    punches = @person.time_clock_punches.where(time_clock_period: period)
    today = Time.current.beginning_of_day

    if (open_punch = punches.where(end_time: nil).order(start_time: :desc).first)
      if open_punch.start_time >= today
        result(:notice, "You're already clocked in to #{period.name} (since #{time(open_punch.start_time)}).", period, open_punch)
      else
        result(:warning, "You're still clocked in to #{period.name} from #{date(open_punch.start_time)}. Clock out below, then clock in, and tell a mentor so they can fix the old punch.", period, open_punch)
      end
    elsif (closed_punch = punches.where(start_time: today..).order(end_time: :desc).first)
      result(:notice, "You clocked out of #{period.name} at #{time(closed_punch.end_time)}. Use Clock In below to clock back in.", period, closed_punch)
    else
      punch = TimeClockPunch.create(person: @person, start_time: Time.current, time_clock_period: period, created_by: "kiosk")
      if punch.persisted?
        result(:success, "You're clocked in to #{period.name} (since #{time(punch.start_time)}).", period, punch)
      else
        result(:danger, "Couldn't clock you in. Please use the buttons below.", period)
      end
    end
  end

  def result(flash_type, message, period = nil, punch = nil)
    Result.new(period: period, punch: punch, flash_type: flash_type, message: message)
  end

  def time(value)
    value.in_time_zone.strftime("%-l:%M %p")
  end

  def date(value)
    value.in_time_zone.strftime("%a, %b %-d")
  end
end
