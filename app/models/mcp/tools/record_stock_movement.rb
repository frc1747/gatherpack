# Records one stock change, as the Used, Moved, Count, Received, Added and Removed forms do
# (Inventory::MovementsController#new and #create).
#
# Mirrors: the item is found in policy_scope(Item) and the places in policy_scope(Location). With
# no location, the form's default: the item's home place (when the viewer sees it) for used,
# received and added, or the only place holding it for used, moved, counted and removed. Then
# authorize create? on the movement (Inventory::Access#may_record?: members only the kinds in
# inventory_member_kinds, managers every kind), and StockMovement.record!, which locks the stock,
# works out a count's difference, refuses what the form refuses (a tracked or inactive item, a
# machine, a move to the same place, a missing reason) and sends the same notices and hooks. For
# counted, quantity is the number seen; for moved, leaving it out moves all of it. Its refusals
# come back as invalid-argument errors with the form's message. One movement per call. Reasons and
# notes stay out of the Rails log. Needs the inventory feature.
class Mcp::Tools::RecordStockMovement < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "record_stock_movement"
  description "Record one stock change: used, moved (to_location_id), counted (quantity is the number you saw), received, " \
    "added or removed. Members may record the kinds the organization allows them (by default used, moved and counted); " \
    "inventory managers every kind. Added and removed need a reason. Returns the change and the stock after it."
  scope :write
  feature :inventory
  input_schema(
    properties: {
      kind: { type: "string", enum: Mcp::InventoryRecords::KINDS },
      item_id: { type: "string", description: "The item (itm_)" },
      location_id: { type: "string", description: "The place (loc_): where from, or where into. Default: the item's usual place." },
      to_location_id: { type: "string", description: "moved: where to (loc_)" },
      quantity: { type: "integer", minimum: 0, maximum: 1_000_000,
                  description: "How many (used default 1; moved default all of it). counted: the number you saw." },
      reason: { type: "string", description: "Why (needed for added and removed)" },
      note: { type: "string" }
    },
    required: %w[kind item_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      id: { type: "string" },
      kind: { type: "string" },
      item: Mcp::Tool::REF_SCHEMA,
      location: Mcp::InventoryRecords::PLACE_SCHEMA,
      to_location: Mcp::InventoryRecords::NULLABLE_PLACE,
      quantity: { type: "integer" },
      counted_quantity: { type: %w[integer null] },
      stock_after: { type: "integer" },
      to_stock_after: { type: %w[integer null] },
      total_after: { type: "integer" },
      running_low: { type: "boolean" }
    },
    required: %w[id kind item location to_location quantity counted_quantity stock_after to_stock_after total_after running_low]
  )

  def call(kind:, item_id:, location_id: nil, to_location_id: nil, quantity: nil, reason: nil, note: nil)
    item = ctx.find(Item, item_id)
    location = location_id ? find_place(location_id) : default_place(item, kind)
    to_location = to_location_id && find_place(to_location_id)
    ctx.authorize!(StockMovement.new(kind: kind, item: item, location: location || first_place(item)), :create?)

    movement = inventory_action do
      StockMovement.record!(kind: kind, item: item, person: ctx.person, location: location, to_location: to_location,
        quantity: quantity, reason: reason, note: note)
    end
    rows = kind == "moved" ? movement.move_rows : [ movement ]
    changed!(movement, *rows.drop(1))
    item.reload
    total = item.total_stock
    {
      id: movement.neat_id,
      kind: movement.kind,
      item: item_ref_json(item),
      location: place_json(movement.location),
      to_location: place_json(to_location && rows.last.location),
      quantity: movement.quantity,
      counted_quantity: movement.counted_quantity,
      stock_after: item.stock_at(movement.location),
      to_stock_after: (item.stock_at(rows.last.location) if kind == "moved"),
      total_after: total,
      running_low: item.low?(total)
    }
  end

  private

  def storage_places
    ctx.policy_scope(Location).active.storage
  end

  def stocked_places(item)
    storage_places.where(id: item.stock_levels.where.not(quantity: 0).select(:location_id)).ordered.to_a
  end

  # The form's default place (MovementsController#set_form).
  def default_place(item, kind)
    home = item.default_location
    home = nil unless home && ctx.policy_scope(Location).exists?(id: home.id)
    return home if home && kind.in?(%w[used received added])

    stocked = stocked_places(item)
    stocked.first if kind.in?(%w[used moved counted removed]) && stocked.one?
  end

  # What the form checks permission against when no place is chosen yet.
  def first_place(item)
    stocked_places(item).first || storage_places.ordered.first
  end
end
