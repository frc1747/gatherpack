# Removes a punch, as TimeClockPunchesController#destroy does (line 85): set_time_clock_punch
# (line 98, in policy_scope(TimeClockPunch), then destroy?, which is update?), and destroy!.
# The one difference from the page: deleting an open punch needs an admin or a manager
# (Mcp::PunchRecords#may_close_punches?), or it would stand in for closing it.
class Mcp::Tools::RemovePunch < Mcp::Tool
  include Mcp::PunchRecords

  tool_name "remove_punch"
  description "Delete a time clock punch, as Delete does on the Time Clock page. A punch you can see but not edit is \"Not allowed\", and only admins and managers can delete an open punch. Returns what was removed."
  scope :write
  feature :time_tracking
  destructive
  input_schema(
    properties: { punch_id: { type: "string", description: "The punch's ID (tcp_)" } },
    required: %w[punch_id]
  )
  output_schema(Mcp::PunchRecords::SCHEMA.merge(
    properties: Mcp::PunchRecords::SCHEMA[:properties].merge(removed: { type: "boolean" }),
    required: Mcp::PunchRecords::SCHEMA[:required] + %w[removed]
  ))

  def call(punch_id:)
    punch = ctx.find(TimeClockPunch, punch_id)
    ctx.authorize!(punch, :destroy?)
    raise Mcp::NotAllowed if punch.end_time.nil? && !may_close_punches?
    shown = punch_json(punch)
    punch.destroy!

    changed!(punch)
    shown.merge(removed: true)
  end
end
