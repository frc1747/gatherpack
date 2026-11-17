# What a manager may clock out at the time kiosk after scanning their card.
#
# Always: every open punch in a period on a team they manage (sub-teams
# included), as upstream's kiosk does. With the "Kiosk: Managers Clock Out
# the People They Manage" setting on, also the open punches of anyone in the
# teams they manage, whichever period the punch is in (or none). Ending a
# punch doesn't change the period, so the period's "added by" permission
# doesn't apply, as with TimeClockPeriodPolicy#punch_out?.
class TimeKiosk::ManagerClockOut
  SETTING = :time_kiosk_managers_clock_out_people

  Group = Struct.new(:period, :punches, keyword_init: true)

  def self.people_enabled?
    Settings[SETTING]
  end

  attr_reader :manager

  def initialize(manager)
    @manager = manager
  end

  # Only someone with a login can act as a manager at the kiosk.
  def allowed?
    manager.present? && manager.user.present?
  end

  # Periods on the teams this person manages.
  def periods
    return TimeClockPeriod.none unless allowed?

    @periods ||= TimeClockPeriod.where(team_id: manager.all_managed_teams.select(:id)).order(:name)
  end

  # The open punches this person may end.
  def punches
    return TimeClockPunch.none unless allowed?

    open = TimeClockPunch.where(end_time: nil)
    scope = open.where(time_clock_period_id: periods.select(:id))
    scope = scope.or(open.where(person_id: manager.all_managed_people.select(:id))) if self.class.people_enabled?
    scope
  end

  # One row per period for the Manager window: each managed period (even with
  # no one clocked in), then any other period a managed person is clocked in
  # to, then punches with no period. The period is nil for the last.
  def groups
    return [] unless allowed?

    by_period = punches.includes(:person, :time_clock_period).to_a.group_by(&:time_clock_period)
    rows = periods.map { |period| Group.new(period: period, punches: by_period.delete(period) || []) }
    unassigned = by_period.delete(nil)
    rows += by_period.sort_by { |period, _| period.name.to_s }.map { |period, list| Group.new(period: period, punches: list) }
    rows << Group.new(period: nil, punches: unassigned) if unassigned
    rows
  end

  def anything?
    groups.any?
  end

  # Ends the open punches this person may end in one period, or with no
  # period when period is nil. Returns how many, or nil when they may not
  # clock out that period at all.
  def clock_out_period!(period)
    selected = period ? punches.where(time_clock_period_id: period.id) : punches.where(time_clock_period_id: nil)
    return if selected.none? && !(period && periods.exists?(period.id))

    end_all(selected)
  end

  # Ends every open punch this person may end. Returns how many, or nil when
  # there's nothing they manage.
  def clock_out_all!
    return unless anything?

    end_all(punches)
  end

  private

  # A punch ends now, or at the end of its period's last day if that's past.
  def end_all(scope)
    now = Time.current
    list = scope.includes(:time_clock_period).to_a
    list.each do |punch|
      max_time = punch.time_clock_period&.end_time&.end_of_day || now
      punch.update(end_time: [ now, max_time ].min, created_by: "kiosk")
    end
    list.size
  end
end
