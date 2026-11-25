# The lists a group manages for inventory, as the pickers on its pages offer them: the active place
# types, stock units, part conditions and reading types, in the order the pickers show them. They
# are what the other inventory tools take IDs of (a place's type, an item's stock unit, a unit's
# condition, a check's readings). Everyone who may use inventory sees them, as every picker shows
# them (authorize :inventory, :use?). Needs the inventory feature.
class Mcp::Tools::ListInventoryLists < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "list_inventory_lists"
  description "The group's inventory lists, active rows in picker order: place_types (with holds_stock and " \
    "holds_installed_parts), stock_units (with the default), part_conditions (with needs_attention and out_of_service) and " \
    "reading_types (with unit). Use their IDs, or names, in the other inventory tools."
  scope :read
  feature :inventory
  input_schema(properties: {})
  output_schema(
    type: "object",
    properties: {
      place_types: { type: "array", items: Mcp::InventoryRecords::TYPE_SCHEMA },
      stock_units: { type: "array", items: Mcp::InventoryRecords::STOCK_UNIT_SCHEMA },
      part_conditions: { type: "array", items: Mcp::InventoryRecords::CONDITION_SCHEMA },
      reading_types: { type: "array", items: Mcp::InventoryRecords::READING_TYPE_SCHEMA }
    },
    required: %w[place_types stock_units part_conditions reading_types]
  )

  def call
    ctx.authorize!(:inventory, :use?)
    Inventory::Lists.defaults.each_key { |list| Inventory::Lists.seed!(list) }
    {
      place_types: LocationType.active.ordered.map { |type| type_json(type) },
      stock_units: StockUnit.active.ordered.map { |unit| stock_unit_json(unit) },
      part_conditions: UnitCondition.active.ordered.map { |condition| condition_json(condition) },
      reading_types: ReadingType.active.ordered.map { |type| reading_type_json(type) }
    }
  end
end
