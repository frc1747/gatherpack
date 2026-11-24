# Takes one action on a tracked unit, as the unit page's buttons do (Inventory::UnitsController):
# install it on a machine or into another unit, take it off, move it, check it, mark it for repair,
# mark it repaired, or retire it.
#
# Mirrors: the unit is found in policy_scope(ItemUnit) and asked the action's own question
# (ItemUnitPolicy, Inventory::Access#may_unit_action?: members the actions in
# inventory_member_unit_actions, managers every action). Places come from policy_scope(Location)
# and an outer unit from policy_scope(ItemUnit), as the page looks them up. Then the ItemUnit action
# method, which checks again, refuses what the page refuses (a retired unit, a machine where storage
# is needed, a missing note for repairs and retiring, a reading the item doesn't ask for) and writes
# the unit's history with the same hooks. Installing a unit marked Needs repair or Broken asks the
# page's question; confirm: true answers it ("install anyway"), which the history records. Refusals
# come back as invalid-argument errors with the page's message. Notes stay out of the Rails log.
# Needs the inventory feature.
class Mcp::Tools::RecordUnitEvent < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "record_unit_event"
  description "Take an action on a tracked part (unit), as its page's buttons do: install (on a place whose type holds installed parts, location_id, or " \
    "into another unit, into_unit_id), take_off (to a storage place, default the item's home), move (to a storage place), " \
    "check (condition, readings and a note; conditions and reading types are the group's lists, see list_inventory_lists), mark_for_repair (note required), repaired (note required) or retire (note " \
    "required). Installing a part marked Needs repair or Broken needs confirm: true. Returns the unit."
  scope :write
  feature :inventory
  input_schema(
    properties: {
      unit_id: { type: "string", description: "The unit (unt_)" },
      action: { type: "string", enum: Mcp::InventoryRecords::UNIT_ACTIONS },
      location_id: { type: "string", description: "install: the place parts get installed on (a place whose type holds installed parts); take_off, move: the storage place (loc_)" },
      into_unit_id: { type: "string", description: "install: the unit to put it in (unt_)" },
      condition: { type: "string",
                   description: "A part condition's ID (ucnd_), key or name. check: its condition now (not an out of service one); " \
                     "mark_for_repair: one that needs attention (default Needs repair); repaired: a working one (default Good)" },
      readings: { type: "object", additionalProperties: { type: "number" },
                  description: "check: { reading type ID (rdty_) or name => value }, for the reading types the item asks for" },
      note: { type: "string", description: "What was seen or done; required for mark_for_repair, repaired and retire" },
      confirm: { type: "boolean", description: "install: install a part marked Needs repair or Broken anyway" }
    },
    required: %w[unit_id action],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      unit: Mcp::InventoryRecords::UNIT_REF_SCHEMA,
      place: Mcp::InventoryRecords::PLACE_SCHEMA,
      event: { type: "object", properties: { id: { type: "string" }, action: { type: "string" }, text: { type: "string" } },
               required: %w[id action text] }
    },
    required: %w[unit place event]
  )

  def call(unit_id:, action:, location_id: nil, into_unit_id: nil, condition: nil, readings: nil, note: nil, confirm: false)
    unit = ctx.find(ctx.policy_scope(ItemUnit).includes(:item, :location, :installed_in, :unit_condition), unit_id)
    ctx.authorize!(unit, :"#{action}?")
    condition = list_row(UnitCondition, condition, "part condition") if condition.present?
    event = inventory_action { act(unit, action, location_id, into_unit_id, condition, readings || {}, note, confirm) }
    unit.reload
    changed!(unit, event)
    { unit: unit_ref_json(unit), place: place_json(unit.location),
      event: { id: event.neat_id, action: event.action, text: inventory_words.unit_event_summary(event) } }
  end

  private

  def act(unit, action, location_id, into_unit_id, condition, readings, note, confirm)
    by = ctx.person
    case action
    when "install" then unit.install!(into: install_target(location_id, into_unit_id), by: by, confirm: confirm, note: note)
    when "take_off" then unit.take_off!(by: by, to: location_id && find_place(location_id), note: note)
    when "move"
      invalid_argument!("Give the place to move it to (location_id)") if location_id.blank?
      unit.move!(to: find_place(location_id), by: by, note: note)
    when "check" then unit.check!(by: by, condition: condition, readings: readings, note: note)
    when "mark_for_repair" then unit.mark_for_repair!(by: by, condition: condition, note: note)
    when "repaired" then unit.repaired!(by: by, condition: condition, note: note)
    when "retire" then unit.retire!(by: by, note: note)
    end
  rescue Inventory::ConfirmNeeded => e
    invalid_argument!("#{e.message} Call again with confirm: true to install it anyway.")
  end

  # A machine, or another unit (UnitsController#install_target).
  def install_target(location_id, into_unit_id)
    return ctx.find(ctx.policy_scope(ItemUnit), into_unit_id) if into_unit_id.present?
    return find_place(location_id) if location_id.present?

    invalid_argument!("Give #{LocationType.installable_words} (location_id) or the part to put it in (into_unit_id)")
  end
end
