# Calendar notes in a date window. Mirrors the notes branch of CalendarController#calendar
# (lines 34-38): policy_scope(CalendarNote), and a note counts if it starts in the window
# or started before and is still going. Window of at most 366 days, inclusive, in the
# app's time zone. CalendarNotePolicy doesn't define show?, so the scope is the only check.
#
# The person filter is the feed's (line 36: where(noteable: id), notes on that ID), within
# that scope. The person must be in policy_scope(Person): the feed takes any ID.
# CalendarNotePolicy::Scope gives a non-admin general notes, their teams' notes, and notes
# on themselves and on their teams' direct members.
class Mcp::Tools::ListCalendarNotes < Mcp::Tool
  MAX_WINDOW_DAYS = 366

  tool_name "list_calendar_notes"
  description "Calendar notes you can see that overlap from..to (YYYY-MM-DD, inclusive, at most 366 days), oldest first. " \
    "Optionally only those on one person. A person you can't see is \"Not found\"."
  scope :read
  feature :events
  input_schema(
    properties: {
      from: { type: "string", description: "First day, YYYY-MM-DD" },
      to: { type: "string", description: "Last day, YYYY-MM-DD" },
      person_id: { type: "string", description: "Only notes on this person (per_ ID)" },
      limit: limit_property
    },
    required: %w[from to]
  )
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            name: { type: "string" },
            description: { type: %w[string null] },
            start_time: { type: "string" },
            end_time: { type: %w[string null] },
            noteable: { anyOf: [ REF_SCHEMA, { type: "null" } ] }
          },
          required: %w[id name description start_time end_time noteable]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(from:, to:, person_id: nil, limit: DEFAULT_LIMIT)
    first, last = date_window(from, to)
    notes = ctx.policy_scope(CalendarNote)
    notes = notes.where(noteable: ctx.find(Person, person_id).id) if person_id
    notes = notes.where(start_time: first..last).or(notes.where(start_time: ..first, end_time: first..))

    list(notes.includes(:noteable).order(:start_time, :id), limit: limit) do |note|
      {
        id: note.neat_id,
        name: note.name,
        description: note.description.presence,
        start_time: time_json(note.start_time),
        end_time: time_json(note.end_time),
        noteable: noteable_json(note.noteable)
      }
    end
  end

  private

  def noteable_json(noteable)
    return nil if noteable.nil?

    noteable.is_a?(Person) ? person_json(noteable) : { id: noteable.neat_id, name: noteable.identifier_name.to_s }
  end

  def date_window(from, to)
    first = parse_date(from, "from")
    last = parse_date(to, "to")
    invalid_argument!("to can't be before from") if last < first
    invalid_argument!("The window can be at most #{MAX_WINDOW_DAYS} days") if (last - first).to_i >= MAX_WINDOW_DAYS

    [ first.in_time_zone.beginning_of_day, last.in_time_zone.end_of_day ]
  end

  def parse_date(value, name)
    raise Date::Error unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    invalid_argument!("#{name} must be a date like 2026-03-31")
  end
end
