# One inventory item as its page shows it (Inventory::ItemsController#show: policy_scope(Item),
# authorize show?): its details, where to buy it (sources, preferred first), its total stock and
# on order, and its stock by place, each with the full place name and when it was last counted.
# Places are those the viewer sees (policy_scope(Location)), with the home place listed at 0 when
# it holds none, as the page lists it. For a tracked item, its units grouped as the item page's
# units panel groups them (available by place, inside other parts, on each machine, in repair,
# retired), from policy_scope(ItemUnit). Needs the inventory feature.
class Mcp::Tools::GetItem < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "get_item"
  description "One inventory item as its page shows it: details, where to buy it, total stock, on order, and stock by place " \
    "with full place names and when each was last counted. A tracked item lists its units by where they are."
  scope :read
  feature :inventory
  input_schema(
    properties: { item_id: { type: "string", description: "The item's ID (itm_)" } },
    required: %w[item_id]
  )
  output_schema(
    type: "object",
    properties: Mcp::InventoryRecords::ITEM_SCHEMA[:properties].merge(
      description: { type: %w[string null] },
      url: { type: %w[string null] },
      note: { type: %w[string null] },
      reorder_quantity: { type: %w[integer null] },
      on_order: { type: "integer" },
      home: Mcp::InventoryRecords::NULLABLE_PLACE,
      sources: {
        type: "array",
        items: {
          type: "object",
          properties: { vendor_name: { type: %w[string null] }, vendor_part_number: { type: %w[string null] }, url: { type: %w[string null] },
                        preferred: { type: "boolean" }, note: { type: %w[string null] } },
          required: %w[vendor_name vendor_part_number url preferred]
        }
      },
      stock: {
        type: "array",
        items: {
          type: "object",
          properties: { place: Mcp::InventoryRecords::PLACE_SCHEMA, quantity: { type: "integer" }, needs_count: { type: "boolean" },
                        last_counted_at: { type: %w[string null] } },
          required: %w[place quantity needs_count last_counted_at]
        }
      },
      units: {
        type: "array",
        items: {
          type: "object",
          properties: { group: { type: "string" }, place: Mcp::InventoryRecords::PLACE_SCHEMA,
                        units: { type: "array", items: Mcp::InventoryRecords::UNIT_REF_SCHEMA } },
          required: %w[group place units]
        }
      },
      reading_fields: { type: "array", items: { type: "object", properties: { name: { type: "string" }, unit: { type: %w[string null] } } } }
    ),
    required: Mcp::InventoryRecords::ITEM_SCHEMA[:required] + %w[on_order home sources stock units reading_fields]
  )

  def call(item_id:)
    item = ctx.find(Item, item_id)
    ctx.authorize!(item, :show?)
    item_json(item, item.total_stock).merge(
      description: item.description.presence,
      url: item.url.presence,
      note: item.note.presence,
      reorder_quantity: item.reorder_quantity,
      on_order: item.on_order,
      home: place_json(visible_home(item)),
      sources: item.item_sources.map { |source| source_json(source) },
      stock: stock_json(item),
      units: item.tracked? ? units_json(item) : [],
      reading_fields: Array(item.reading_fields).map { |field| { name: field["name"].to_s, unit: field["unit"].presence } }
    )
  end

  private

  # The item's default place, when the viewer sees it (Inventory::BaseController#visible_default_location).
  def visible_home(item)
    place = item.default_location
    place if place && ctx.policy_scope(Location).exists?(id: place.id)
  end

  def source_json(source)
    { vendor_name: source.vendor_name.presence, vendor_part_number: source.vendor_part_number.presence, url: source.url.presence,
      preferred: source.preferred?, note: source.note.presence }
  end

  def stock_json(item)
    levels = item.stock_levels.where.not(quantity: 0).where(location_id: ctx.policy_scope(Location).select(:id)).includes(:location).to_a
    home = item.home_location
    if home && levels.none? { |level| level.location_id == home.id } && ctx.allowed?(home, :show?)
      levels.unshift(StockLevel.new(item: item, location: home, quantity: 0))
    end
    counted = item.stock_movements.counted.where(reverses_id: nil).group(:location_id).maximum(:created_at)
    names = inventory_words.inventory_full_names(levels.map(&:location))
    levels.map do |level|
      { place: place_json(level.location, names), quantity: level.quantity, needs_count: level.quantity.negative?,
        last_counted_at: time_json(counted[level.location_id]) }
    end
  end

  # The units panel's groups, in its order.
  def units_json(item)
    units = ctx.policy_scope(item.item_units).includes(:location, :installed_in, :item).order(:code).to_a
    retired, current = units.partition(&:condition_retired?)
    repair, working = current.partition(&:flagged?)
    on_machines, stored = working.partition(&:on_machine?)
    inside, spare = stored.partition(&:installed_in_id?)
    groups = [ [ "Available", spare ], [ "Inside other parts", inside ] ]
    on_machines.group_by(&:location).sort_by { |machine, _| machine.name }.each { |machine, list| groups << [ "On #{machine.name}", list ] }
    groups += [ [ "In repair", repair ], [ "Retired", retired ] ]
    names = inventory_words.inventory_full_names(units.map(&:location).uniq)
    groups.flat_map do |heading, list|
      list.group_by(&:location).map { |place, members| { group: heading, place: place_json(place, names), units: members.map { |unit| unit_ref_json(unit) } } }
    end
  end
end
