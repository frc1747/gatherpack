# Changes a punch, as TimeClockPunchesController#update does (lines 75-82):
# set_time_clock_punch (line 98, in policy_scope(TimeClockPunch), then update?), the
# permitted attributes (line 117), created_by set to the viewer, and save, so the model's
# permission_check and valid_times apply. null clears end time (reopens), period and note,
# as a blank does on the form. A blank start time crashes the model on a period punch, so
# starts_at takes only a time.
#
# The one difference from the page: giving an open punch an end time needs an admin or a
# manager (Mcp::PunchRecords#may_close_punches?), so a member can't end their own from
# anywhere. The page still allows it in some cases (BL-028).
#
# The spec asks for create? when a punch moves to another person, "as the controller
# does". This build's controller checks nothing more and its policy has no create?, so the
# gate on a new person is the one record_punch has (Mcp::PunchRecords#authorize_recording!).
# A build whose policy defines create? applies it on a move to another person or period.
class Mcp::Tools::UpdatePunch < Mcp::Tool
  include Mcp::PunchRecords

  tool_name "update_punch"
  description "Change a time clock punch, as Edit does on the Time Clock page; only what you send changes. " \
    "A punch you can see but not edit, or one you'd move to someone you don't manage, is \"Not allowed\"; a period's permission can refuse it too. Only admins and managers can give an open punch an end time. " \
    "Returns the punch as list_punches shows it."
  scope :write
  feature :time_tracking
  input_schema(
    properties: {
      punch_id: { type: "string", description: "The punch's ID (tcp_)" },
      starts_at: { type: "string", description: "Start, like 2026-03-31T18:00:00, in the site's time zone unless it has an offset" },
      ends_at: { type: %w[string null], description: "End, in the same form; null reopens the punch" },
      period_id: { type: %w[string null], description: "Move to this period (tcpd_); null takes it out of its period" },
      person_id: { type: "string", description: "Move to this person (per_)" },
      note: { type: %w[string null], description: "null clears it" }
    },
    required: %w[punch_id],
    closed: true
  )
  output_schema(Mcp::PunchRecords::SCHEMA)

  CHANGES = %i[starts_at ends_at period_id person_id note].freeze

  def call(punch_id:, **changes)
    invalid_argument!("Give at least one of #{CHANGES.to_sentence(last_word_connector: " or ")}") if changes.empty?

    punch = ctx.find(TimeClockPunch, punch_id)
    ctx.authorize!(punch, :update?)
    assign_changes(punch, changes)
    raise Mcp::NotAllowed if closing?(punch) && !may_close_punches?
    authorize_move!(punch)
    save_punch!(punch)

    changed!(punch) if punch.saved_changes?
    punch_json(punch)
  end

  private

  def assign_changes(punch, changes)
    refuse_control_characters!("note", changes[:note])
    punch.person = ctx.find(Person, changes[:person_id]) if changes.key?(:person_id) && changes[:person_id] != punch.person.neat_id
    punch.time_clock_period = new_period(punch, changes[:period_id]) if changes.key?(:period_id)
    punch.start_time = parse_time(changes[:starts_at], "starts_at") if changes.key?(:starts_at)
    punch.end_time = changes[:ends_at] && parse_time(changes[:ends_at], "ends_at") if changes.key?(:ends_at)
    punch.note = changes[:note] if changes.key?(:note)
  end

  def closing?(punch)
    punch.end_time_was.nil? && punch.end_time.present?
  end

  # The punch's own period may be one the viewer can't look up; naming it again isn't a move.
  def new_period(punch, period_id)
    return nil if period_id.nil?
    return punch.time_clock_period if punch.time_clock_period&.neat_id == period_id

    ctx.find(TimeClockPeriod, period_id)
  end

  def authorize_move!(punch)
    ctx.authorize!(punch, :create?) if (punch.person_id_changed? || punch.time_clock_period_id_changed?) && ctx.defines?(punch, :create?)
    raise Mcp::NotAllowed if punch.person_id_changed? && !may_record_for?(punch)
  end
end
