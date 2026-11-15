# What the inventory tools share: an item, a place and a tracked unit as the inventory pages
# show them, and the lookups those pages make.
#
# Items, places and units are found through their policy scopes (ItemPolicy, LocationPolicy,
# ItemUnitPolicy), as the pages find them, so a member sees their teams' records (and those
# above) only while they may use inventory, and inactive ones only where they manage them. A
# place's full name ("Shop › Cabinet A › Bin 3") is the path the pages show. An
# Inventory::Refused comes back as an invalid-argument error with the page's message; a refusal
# by policy is "Not allowed". Unit history and actions use the unit page's own words
# (Inventory::UnitsHelper, through Mcp::InventoryWords).
module Mcp::InventoryRecords
  KINDS = %w[used moved counted received added removed].freeze
  UNIT_ACTIONS = %w[install take_off move check mark_for_repair repaired retire].freeze
  CONDITIONS = %w[new good worn needs_repair broken retired].freeze

  PLACE_SCHEMA = {
    type: "object",
    properties: { id: { type: "string" }, name: { type: "string" }, full_name: { type: "string" }, kind: { type: "string" } },
    required: %w[id name full_name kind]
  }.freeze
  NULLABLE_PLACE = { anyOf: [ PLACE_SCHEMA, { type: "null" } ] }.freeze

  ITEM_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      team: Mcp::Tool::REF_SCHEMA,
      category: { type: %w[string null] },
      manufacturer: { type: %w[string null] },
      manufacturer_part_number: { type: %w[string null] },
      unit: { type: "string" },
      tracked: { type: "boolean" },
      active: { type: "boolean" },
      total_stock: { type: "integer" },
      reorder_point: { type: %w[integer null] },
      running_low: { type: "boolean" },
      out_of_stock: { type: "boolean" }
    },
    required: %w[id name team unit tracked active total_stock reorder_point running_low out_of_stock]
  }.freeze

  UNIT_REF_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" }, code: { type: "string" }, item: Mcp::Tool::REF_SCHEMA,
      condition: { type: "string", enum: CONDITIONS }, condition_label: { type: "string" },
      installed_in: { anyOf: [ { type: "object", properties: { id: { type: "string" }, code: { type: "string" } } }, { type: "null" } ] }
    },
    required: %w[id code item condition condition_label installed_in]
  }.freeze

  private

  def inventory_words
    @inventory_words ||= Mcp::InventoryWords.new(ctx.user)
  end

  def inventory_access
    Inventory::Access.for(ctx.person)
  end

  # Runs a domain action, giving back its refusal or validation error as the page's message.
  def inventory_action
    yield
  rescue Inventory::Refused => e
    invalid_argument!(e.message)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  # A place the viewer sees, by ID.
  def find_place(id)
    ctx.find(Location, id)
  end

  def item_ref_json(item)
    { id: item.neat_id, name: item.name }
  end

  def item_json(item, total)
    {
      id: item.neat_id,
      name: item.name,
      team: team_json(item.team),
      category: item.category.presence,
      manufacturer: item.manufacturer.presence,
      manufacturer_part_number: item.manufacturer_part_number.presence,
      unit: item.unit.presence || "each",
      tracked: item.tracked?,
      active: item.active?,
      total_stock: total,
      reorder_point: item.reorder_point,
      running_low: item.low?(total),
      out_of_stock: !item.reorder_point.nil? && item.out_of_stock?(total)
    }
  end

  # full_names is { location id => full name } from inventory_words.inventory_full_names.
  def place_json(location, full_names = nil)
    return nil if location.nil?

    full_name = full_names&.dig(location.id) || location.full_name
    { id: location.neat_id, name: location.name, full_name: full_name, kind: location.kind }
  end

  def unit_ref_json(unit)
    {
      id: unit.neat_id,
      code: unit.identifier_name,
      item: item_ref_json(unit.item),
      condition: unit.condition,
      condition_label: unit.condition_label,
      installed_in: unit.installed_in && { id: unit.installed_in.neat_id, code: unit.installed_in.identifier_name }
    }
  end
end
