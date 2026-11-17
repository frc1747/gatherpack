# One tracked unit as its page shows it (Inventory::UnitsController#show: policy_scope(ItemUnit),
# authorize show?): where it is (a storage place, or a machine and the unit it's inside), its
# condition, what's inside it, the latest readings and the readings a check asks for, the actions
# its page offers this viewer (Inventory::UnitsHelper#unit_actions_for), and its history, newest
# first, in the page's words. By ID, or by code: the code, serial number or label link a person
# types or scans, looked up as Install a part and the unit search do (Inventory::UnitLookup), among
# the active units the viewer sees. Readings leave out undone checks, as the page does. Needs the
# inventory feature.
class Mcp::Tools::GetUnit < Mcp::Tool
  include Mcp::InventoryRecords
  include Inventory::UnitLookup

  HISTORY = 50

  tool_name "get_unit"
  description "One tracked part (unit) as its page shows it: where it is, condition, what's inside it, latest readings, the " \
    "actions you can take on it, and its history. Give unit_id, or code (its code, serial number or label link)."
  scope :read
  feature :inventory
  input_schema(
    properties: {
      unit_id: { type: "string", description: "The unit's ID (unt_)" },
      code: { type: "string", description: "Or its code, serial number or label link" }
    }
  )
  output_schema(
    type: "object",
    properties: Mcp::InventoryRecords::UNIT_REF_SCHEMA[:properties].merge(
      name: { type: %w[string null] },
      serial_number: { type: %w[string null] },
      condition_note: { type: %w[string null] },
      in_service_on: { type: %w[string null] },
      active: { type: "boolean" },
      place: Mcp::InventoryRecords::PLACE_SCHEMA,
      contents: { type: "array", items: Mcp::InventoryRecords::UNIT_REF_SCHEMA },
      latest_readings: { type: "object" },
      reading_fields: { type: "array", items: { type: "object" } },
      actions: { type: "array", items: { type: "string", enum: Mcp::InventoryRecords::UNIT_ACTIONS } },
      history: {
        type: "array",
        items: {
          type: "object",
          properties: { id: { type: "string" }, action: { type: "string" }, text: { type: "string" }, by: { type: %w[string null] },
                        at: { type: "string" }, note: { type: %w[string null] }, readings: { type: "object" },
                        installed_anyway: { type: "boolean" }, undone: { type: "boolean" } },
          required: %w[id action text by at note readings installed_anyway undone]
        }
      }
    ),
    required: Mcp::InventoryRecords::UNIT_REF_SCHEMA[:required] + %w[place contents latest_readings reading_fields actions history]
  )

  def call(unit_id: nil, code: nil)
    invalid_argument!("Give unit_id or code") if unit_id.blank? && code.blank?

    unit = unit_id.present? ? ctx.find(ctx.policy_scope(ItemUnit).includes(:item, :location, :installed_in), unit_id) : by_code(code)
    ctx.authorize!(unit, :show?)
    events = unit.events.includes(:person, :from_location, :to_location, :from_unit, :to_unit, :via_unit).to_a
    undone = events.filter_map(&:reverses_id).to_set
    unit_ref_json(unit).merge(
      name: unit.name.presence,
      serial_number: unit.serial_number.presence,
      condition_note: unit.condition_note.presence,
      in_service_on: date_json(unit.in_service_on),
      active: unit.active?,
      place: place_json(unit.location),
      contents: ctx.policy_scope(unit.contents).includes(:item, :installed_in).order(:code).map { |inner| unit_ref_json(inner) },
      latest_readings: inventory_words.unit_latest_readings(inventory_words.unit_readings_rows(unit)),
      reading_fields: Array(unit.item.reading_fields),
      actions: inventory_words.unit_actions_for(unit),
      history: events.reverse.first(HISTORY).map { |event| event_json(event, undone) }
    )
  end

  private

  # Inventory::UnitLookup asks for the viewer's scope.
  def policy_scope(scope)
    ctx.policy_scope(scope)
  end

  def by_code(code)
    inventory_action { unit_from_code(code) }
  rescue Mcp::InvalidArgument => e
    raise Mcp::NotFound, e.message if e.message.start_with?("No part has the code", "That label isn't")

    raise
  end

  def event_json(event, undone)
    {
      id: event.neat_id,
      action: event.action,
      text: inventory_words.unit_event_summary(event),
      by: event.person&.identifier_name,
      at: time_json(event.created_at),
      note: event.note.presence,
      readings: event.readings.to_h,
      installed_anyway: event.confirmed? == true,
      undone: undone.include?(event.id)
    }
  end
end
