# Closes open punches, as the kiosk's punch_out, punch_out_period and punch_out_all do
# (TimeKioskController lines 40, 52, 66): now, capped at the end of the period's last day
# (lines 44-45), with one rule for all three forms instead of the kiosk's three:
#
# - Admins: any open punch.
# - Managers: open punches in periods whose team they manage (all_managed_teams, as
#   TimeKiosk#managed_periods), including "added by admin" periods, as All Periods does.
#   Their own open punch too.
# - Anyone else: their own open punch only.
#
# So this is wider than TimeClockPunchPolicy#update?, which update_punch uses. A punch in
# no period can only be closed by an admin or its owner here; a manager uses update_punch.
#
# all: true covers the periods only, as All Periods does: every period for an admin, the
# managed teams' for a manager, so nothing for anyone else. A punch in no period, or a
# manager's own in another team's period, needs person_id.
#
# A punch the viewer can neither see nor close isn't listed at all: a skipped entry would
# say that person is clocked in. So skipped holds those in policy_scope(TimeClockPunch).
#
# created_by isn't a column. It only tells the model's permission_check who's asking, and
# for a manager that check refuses an "added by admin" period, so this sets "kiosk" as the
# kiosk does: nothing stores it, and the audit log's user and the call log say who closed
# the punch. valid_times still applies, so one that would end before it starts is skipped.
class Mcp::Tools::ClockOut < Mcp::Tool
  include Mcp::PunchRecords

  tool_name "clock_out"
  description "Clock people out, as the kiosk's Clock Out does, for one person, one period or all: true, each punch ending now or at the end of its period's last day. " \
    "Admins close any open punch, managers those in their teams' periods, everyone their own; others you can see are skipped as \"Not allowed\". " \
    "Use dry_run first to see what would change."
  scope :write
  feature :time_tracking
  bulk
  input_schema(
    properties: {
      person_id: { type: "string", description: "This person's open punches (per_ ID)" },
      period_id: { type: "string", description: "This period's open punches (tcpd_ ID)" },
      all: { type: "boolean", description: "true: open punches in every period on the teams you manage (admins: every period)" },
      dry_run: dry_run_property
    },
    closed: true
  )
  output_schema(bulk_output_schema(Mcp::PunchRecords::SCHEMA))

  def call(person_id: nil, period_id: nil, all: false, dry_run: false)
    invalid_argument!("Give exactly one of person_id, period_id or all: true") unless [ person_id, period_id, all.presence ].compact.one?

    now = Time.current
    flags = nil
    bulk_write(open_punches(person_id, period_id, all), dry_run: dry_run,
      check: ->(punch) { may_close?(punch) && closes_cleanly?(punch, now) },
      json: ->(punch) { punch_json(punch, flags ||= flags_by_punch(chosen_punches)) }) { |punch| punch.save }
  end

  private

  def open_punches(person_id, period_id, all)
    open = TimeClockPunch.still_clocked_in
    chosen = if all
      ctx.user.admin ? open.where.not(time_clock_period_id: nil) : open.where(time_clock_period_id: managed_periods.select(:id))
    elsif person_id
      open.where(person: ctx.find(Person, person_id))
    else
      open.where(time_clock_period: ctx.find(TimeClockPeriod, period_id))
    end
    visible = ctx.policy_scope(TimeClockPunch).or(TimeClockPunch.where(time_clock_period_id: managed_periods.select(:id)))

    @chosen_punches = chosen.where(id: visible.select(:id)).includes(:person, time_clock_period: :team).order(:start_time, :id).to_a
  end

  attr_reader :chosen_punches

  def managed_periods
    TimeClockPeriod.where(team_id: managed_team_ids)
  end

  def managed_team_ids
    @managed_team_ids ||= ctx.person.all_managed_teams.pluck(:id)
  end

  def may_close?(punch)
    ctx.user.admin || punch.person_id == ctx.person.id || managed_team_ids.include?(punch.time_clock_period&.team_id)
  end

  # Sets the end time here, so a dry run shows it and refuses what a real run would.
  def closes_cleanly?(punch, now)
    period_end = punch.time_clock_period&.end_time&.end_of_day
    punch.end_time = period_end && period_end < now ? period_end : now
    punch.created_by = "kiosk"
    invalid_argument!(punch.errors.full_messages.to_sentence) unless punch.valid?

    true
  end
end
