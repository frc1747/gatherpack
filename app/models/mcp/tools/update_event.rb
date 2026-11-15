# Changes an event, as EventsController#update does.
#
# Mirrors: set_event (line 80, authorize update?: admins and managers of the event's team,
# ancestors' managers included), update (line 64) with event_params (line 85), so the model's
# validations and any callbacks a connector adds to Event run as they do on the page. The event
# is looked up in policy_scope(Event) rather than with Event.find, which only decides between
# "Not found" and "Not allowed": everyone update? allows is in that scope.
#
# A new team: the controller authorizes only the event's current team, so a hand-made PATCH can
# move it anywhere. The form offers only managed_teams, and a blank only to admins (_form line
# 24). update? asked again with the new team is that same rule. The other lookups are the form's
# too: every event type (f.association), periods in policy_scope(TimeClockPeriod).
#
# null clears what a blank clears on the form: description, end time, location, team, period and
# limit. name and starts_at are required by the model, so they take only a value. Times are read
# as Mcp::PunchRecords reads them, and its check keeps out of single-line values what the form's
# inputs can't send. The result is get_event's, plus the two attributes it doesn't show.
class Mcp::Tools::UpdateEvent < Mcp::Tool
  include Mcp::EventRecords
  include Mcp::PunchRecords

  INT4_MAX = 2_147_483_647
  CHANGES = %i[name description starts_at ends_at location event_type_id team_id locked time_clock_period_id checkin_limit].freeze

  tool_name "update_event"
  description "Change an event, as Edit does on the event's page; only what you send changes, and changing the time does what an edit on the page does. " \
    "An event you can see but not edit, or a team you don't manage, is \"Not allowed\". Returns the event as get_event shows it."
  scope :write
  feature :events
  input_schema(
    properties: {
      event_id: { type: "string", description: "The event's ID (evt_)" },
      name: { type: "string", description: "The event's name" },
      description: { type: %w[string null], description: "null clears it" },
      starts_at: { type: "string", description: "Start, like 2026-03-31T18:00:00, in the site's time zone unless it has an offset" },
      ends_at: { type: %w[string null], description: "End, in the same form; null clears it" },
      location: { type: %w[string null], description: "null clears it" },
      event_type_id: { type: "string", description: "The event type's ID (evtp_), from list_event_types" },
      team_id: { type: %w[string null], description: "Move to this team (tm_); only an admin can send null" },
      locked: { type: "boolean", description: "Whether only admins and the team's managers can check people in" },
      time_clock_period_id: { type: %w[string null], description: "The period its hours count toward (tcpd_); null clears it" },
      checkin_limit: { type: %w[integer null], minimum: -INT4_MAX - 1, maximum: INT4_MAX, description: "Most check-ins allowed; null or 0 is no limit" }
    },
    required: %w[event_id],
    closed: true
  )
  output_schema(Mcp::EventRecords::SCHEMA.merge(
    properties: Mcp::EventRecords::SCHEMA[:properties].merge(
      locked: { type: "boolean" },
      time_clock_period: { anyOf: [ REF_SCHEMA, { type: "null" } ] }
    ),
    required: Mcp::EventRecords::SCHEMA[:required] + %w[locked time_clock_period]
  ))

  def call(event_id:, **changes)
    invalid_argument!("Give at least one of #{CHANGES.to_sentence(last_word_connector: " or ")}") if changes.empty?

    event = ctx.find(Event, event_id)
    ctx.authorize!(event, :update?)
    assign_changes(event, changes)
    ctx.authorize!(event, :update?) if event.team_id_changed?
    invalid_argument!(event.errors.full_messages.to_sentence) unless event.save

    changed!(event) if event.saved_changes?
    period = event.time_clock_period
    event_json(event).merge(locked: event.locked == true, time_clock_period: period && { id: period.neat_id, name: period.name.to_s })
  end

  private

  def assign_changes(event, changes)
    refuse_control_characters!("name", changes[:name])
    refuse_control_characters!("location", changes[:location])
    event.assign_attributes(changes.slice(:name, :description, :location, :locked, :checkin_limit))
    event.start_time = parse_time(changes[:starts_at], "starts_at") if changes.key?(:starts_at)
    event.end_time = changes[:ends_at] && parse_time(changes[:ends_at], "ends_at") if changes.key?(:ends_at)
    event.event_type = ctx.find(EventType.all, changes[:event_type_id]) if changes.key?(:event_type_id)
    event.team = changes[:team_id] && ctx.find(Team, changes[:team_id]) if changes.key?(:team_id)
    event.time_clock_period = new_period(event, changes[:time_clock_period_id]) if changes.key?(:time_clock_period_id)
  end

  # The event's own period may be one the viewer can't look up; naming it again isn't a move.
  def new_period(event, period_id)
    return nil if period_id.nil?
    return event.time_clock_period if event.time_clock_period&.neat_id == period_id

    ctx.find(TimeClockPeriod, period_id)
  end
end
