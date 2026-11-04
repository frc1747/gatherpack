# Records a punch, as TimeClockPunchesController#create does (lines 63-72): build from
# the permitted attributes (line 117), set created_by to the viewer, save. The model's
# permission_check then applies the period's permission: "added by admin" needs an admin,
# "added by manager" a manager of its team, "added by team member" a member of its team,
# and the person must be on the period's team. Its valid_times applies the period's dates.
#
# The policy doesn't define create?, so the POST checks no person at all: see
# Mcp::PunchRecords#authorize_recording! for the gate this uses instead, the form's person
# list. Narrower than the POST in that, and because the person and period must be in
# policy_scope(Person) and policy_scope(TimeClockPeriod), as the form's searches are.
class Mcp::Tools::RecordPunch < Mcp::Tool
  include Mcp::PunchRecords

  tool_name "record_punch"
  description "Add a time clock punch, as New Time Clock Punch does; it stays open if ends_at is left out. " \
    "You can record for yourself and people you manage; a period's permission can refuse that with \"Not allowed\", and someone you can't see is \"Not found\". " \
    "Returns the punch as list_punches shows it."
  scope :write
  feature :time_tracking
  input_schema(
    properties: {
      person_id: { type: "string", description: "The person's ID (per_)" },
      period_id: { type: "string", description: "The period's ID (tcpd_); leave out for a punch in no period" },
      starts_at: { type: "string", description: "Start, like 2026-03-31T18:00:00, in the site's time zone unless it has an offset" },
      ends_at: { type: "string", description: "End, in the same form; leave out to keep the punch open" },
      note: { type: "string" }
    },
    required: %w[person_id starts_at],
    closed: true
  )
  output_schema(Mcp::PunchRecords::SCHEMA)

  def call(person_id:, starts_at:, period_id: nil, ends_at: nil, note: nil)
    punch = TimeClockPunch.new(person: ctx.find(Person, person_id))
    punch.time_clock_period = ctx.find(TimeClockPeriod, period_id) if period_id
    authorize_recording!(punch)

    refuse_control_characters!("note", note)
    punch.assign_attributes(start_time: parse_time(starts_at, "starts_at"), end_time: ends_at && parse_time(ends_at, "ends_at"), note: note)
    save_punch!(punch)

    changed!(punch)
    punch_json(punch)
  end
end
