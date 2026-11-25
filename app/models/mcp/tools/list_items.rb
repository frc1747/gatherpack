# Inventory items the viewer can see, as Inventory's search and the Items list show them
# (Inventory::SearchController, Inventory::ItemsController#index: authorize index?, which is
# inventory_users; policy_scope(Item), by name). query matches what Item.search matches: the
# name, maker part number, category or a source's part number. Inactive items are left out, as
# the search leaves them out, unless include_inactive, and then only those the viewer manages
# (the scope's rule). Total stock is Inventory::Stock's (active places, negatives as zero; a
# tracked item's available units), and running_low and out_of_stock are the pages' badges.
# Pages: offset skips that many items, and next_offset is where the next page starts (null on
# the last page), alongside truncated. Needs the inventory feature.
class Mcp::Tools::ListItems < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "list_items"
  description "Inventory items you can see, by name, with part numbers, unit, total stock, reorder point and whether each " \
    "is running low. Filters: query (name, part number or category), category, team_id, low_only. When truncated, call " \
    "again with offset: next_offset for the next page."
  scope :read
  feature :inventory
  input_schema(
    properties: {
      query: { type: "string", description: "Words in the name, a part number or the category" },
      category: { type: "string", description: "Only this category" },
      team_id: { type: "string", description: "Only this team's items (tm_)" },
      low_only: { type: "boolean", description: "Only items running low: at or below their reorder point (default false)" },
      include_inactive: { type: "boolean", description: "Also inactive items you manage (default false)" },
      limit: limit_property,
      offset: { type: "integer", minimum: 0, maximum: 1_000_000, description: "Skip this many items, for the next page (default 0)" }
    }
  )
  output_schema(
    type: "object",
    properties: {
      items: { type: "array", items: Mcp::InventoryRecords::ITEM_SCHEMA },
      truncated: { type: "boolean" },
      next_offset: { type: %w[integer null], description: "The offset of the next page, or null on the last page" }
    },
    required: %w[items truncated next_offset]
  )

  def call(query: nil, category: nil, team_id: nil, low_only: false, include_inactive: false, limit: DEFAULT_LIMIT, offset: 0)
    ctx.authorize!(Item, :index?)
    items = ctx.policy_scope(Item).includes(:team).order(:name, :id)
    items = items.where(active: true) unless include_inactive
    items = matching(items, query) if query.present?
    items = items.where(category: category) if category.present?
    items = items.where(team_id: ctx.find(Team, team_id).id) if team_id
    limit = limit.to_i.clamp(1, MAX_LIMIT)
    return low_items(items, limit, offset) if low_only

    page = list(items.offset(offset), limit: limit) { |item| item }
    totals = Inventory::Stock.totals(page[:items])
    paged(page[:items].map { |item| item_json(item, totals[item.id]) }, page[:truncated], offset)
  end

  private

  def matching(items, query)
    pattern = "%#{Item.sanitize_sql_like(query.strip)}%"
    by_source = ItemSource.where("vendor_part_number ILIKE :p", p: pattern).select(:item_id)
    items.where("items.name ILIKE :p OR items.manufacturer_part_number ILIKE :p OR items.category ILIKE :p", p: pattern)
      .or(items.where(id: by_source))
  end

  # Running low needs each item's total, so these are worked out over every item with a reorder point.
  def low_items(items, limit, offset)
    candidates = items.where.not(reorder_point: nil).to_a
    totals = Inventory::Stock.totals(candidates)
    low = candidates.select { |item| item.low?(totals[item.id]) }.drop(offset)
    paged(low.first(limit).map { |item| item_json(item, totals[item.id]) }, low.size > limit, offset)
  end

  def paged(items, truncated, offset)
    { items: items, truncated: truncated, next_offset: (offset + items.size if truncated) }
  end
end
