# Sign-up sheets the viewer can use, as the sign-up sheets page lists them
# (SignupSheetsController#index): policy_scope(SignupSheet) less archived
# sheets, and of those the open ones plus any the viewer runs
# (SignupSheet#organizer?), so a closed or draft sheet shows only to its
# organizers. Each sheet is checked again with SignupSheetPolicy#show?.
# Sheets are listed by title. With from and/or to (YYYY-MM-DD, inclusive, in
# the app's time zone) only sheets with an event starting in that window are
# listed and the counts cover that window's slots; with neither, upcoming
# events only (from today). The counts are the totals the sheet page shows on
# each slot, never names: filled is places or units taken by active and
# fulfilled sign-ups, open is what is left in slots with a cap, and
# unlimited_slots counts slots without one. Slots turned off aren't counted.
class Mcp::Tools::ListSignupSheets < Mcp::Tool
  include Mcp::Tools::SignupFormat

  tool_name "list_signup_sheets"
  description "Sign-up sheets you can use or run, by title, with their team, status, next event in the window and how many " \
    "places are filled and open. `from` and `to` (YYYY-MM-DD, inclusive) limit to sheets with an event starting in that window; " \
    "the default is upcoming events. A closed or draft sheet shows only to its organizers."
  scope :read
  feature :signups
  input_schema(
    properties: {
      from: { type: "string", description: "First day, YYYY-MM-DD (default: today)" },
      to: { type: "string", description: "Last day, YYYY-MM-DD (default: no end)" },
      limit: limit_property
    }
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
            title: { type: "string" },
            status: { type: "string", enum: %w[draft open closed archived] },
            team: REF_SCHEMA,
            organizer: { type: "boolean" },
            next_event: { anyOf: [ EVENT_SCHEMA, { type: "null" } ] },
            filled: { type: "integer" },
            open: { type: "integer" },
            unlimited_slots: { type: "integer" }
          },
          required: %w[id title status team organizer next_event filled open unlimited_slots]
        }
      },
      truncated: { type: "boolean" }
    },
    required: %w[items truncated]
  )

  def call(from: nil, to: nil, limit: DEFAULT_LIMIT)
    window = date_window(from, to)
    sheets = ctx.policy_scope(SignupSheet).visible.includes(:team).to_a
    sheets = sheets.select { |sheet| ctx.allowed?(sheet, :show?) }
    organized = sheets.select { |sheet| sheet.organizer?(ctx.person) }.map(&:id)
    sheets = sheets.select { |sheet| sheet.open? || organized.include?(sheet.id) }

    events = Event.joins(:signup_sheet_events).where(signup_sheet_events: { signup_sheet_id: sheets.map(&:id) }, start_time: window)
      .select("events.*, signup_sheet_events.signup_sheet_id AS sheet_id").order(:start_time, :id).to_a.group_by { |event| event[:sheet_id] }
    shown = SignupSheet.where(id: sheets.map(&:id).select { |id| events.key?(id) })
    slots = SignupSlot.joins(:signup_position).where(signup_positions: { signup_sheet_id: shown.select(:id) }, disabled: false,
      event_id: events.values.flatten.map(&:id)).includes(:signup_position, :signups).group_by { |slot| slot.signup_position.signup_sheet_id }

    list(shown.includes(:team).order(:title, :id), limit: limit) do |sheet|
      sheet_slots = slots.fetch(sheet.id, []).select { |slot| events[sheet.id].any? { |event| event.id == slot.event_id } }
      capped = sheet_slots.select(&:capacity_value)
      {
        id: sheet.neat_id,
        title: sheet.title,
        status: sheet.status,
        team: team_json(sheet.team),
        organizer: organized.include?(sheet.id),
        next_event: event_json(events[sheet.id].first),
        filled: sheet_slots.sum { |slot| slot_used(slot) },
        open: capped.sum { |slot| slot_open(slot) },
        unlimited_slots: sheet_slots.size - capped.size
      }
    end
  end

  private

  # from (default today) to to (default none), as times in the app's zone.
  def date_window(from, to)
    first = from ? parse_date(from, "from") : Time.zone.today
    last = to ? parse_date(to, "to") : nil
    invalid_argument!("to can't be before from") if last && last < first

    first.in_time_zone.beginning_of_day..(last&.in_time_zone&.end_of_day)
  end

  def parse_date(value, name)
    raise Date::Error unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    invalid_argument!("#{name} must be a date like 2026-03-31")
  end
end
