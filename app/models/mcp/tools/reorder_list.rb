# The reorder list (Inventory::ReorderController#index: authorize :inventory, :reorder?, which is
# inventory managers (by grant row) and admins): active items within the viewer's managed reach
# whose total stock plus on order is at or below the reorder point (Inventory::Reorder), grouped by
# the preferred source's vendor name with "No source yet" first and out of stock first in each
# group, with the suggested quantity. Anyone the Reorder page turns away is "Not allowed". Filters
# by team and category, as the page's. Needs the inventory feature.
class Mcp::Tools::ReorderList < Mcp::Tool
  include Mcp::InventoryRecords

  tool_name "reorder_list"
  description "The reorder list: items you manage that are running low (stock plus on order at or below the reorder point), " \
    "grouped by where to buy them, with stock, on order, suggested quantity and the preferred source. Inventory managers only. " \
    "Filters: team_id, category."
  scope :read
  feature :inventory
  input_schema(
    properties: {
      team_id: { type: "string", description: "Only this team's items (tm_)" },
      category: { type: "string", description: "Only this category" }
    }
  )
  output_schema(
    type: "object",
    properties: {
      groups: {
        type: "array",
        items: {
          type: "object",
          properties: {
            vendor_name: { type: "string" },
            rows: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  item: Mcp::InventoryRecords::ITEM_SCHEMA, on_order: { type: "integer" }, suggested_quantity: { type: "integer" },
                  source: {
                    anyOf: [
                      { type: "object", properties: { vendor_name: { type: %w[string null] }, vendor_part_number: { type: %w[string null] },
                                                       url: { type: %w[string null] } } },
                      { type: "null" }
                    ]
                  }
                },
                required: %w[item on_order suggested_quantity source]
              }
            }
          },
          required: %w[vendor_name rows]
        }
      }
    },
    required: %w[groups]
  )

  def call(team_id: nil, category: nil)
    ctx.authorize!(:inventory, :reorder?)
    team = team_id && ctx.find(Team, team_id)
    reorder = Inventory::Reorder.new(ctx.person, team_id: team&.id, category: category)
    {
      groups: reorder.groups.map do |name, rows|
        { vendor_name: name, rows: rows.map { |row| row_json(row) } }
      end
    }
  end

  private

  def row_json(row)
    source = row.source
    {
      item: item_json(row.item, row.total),
      on_order: row.on_order,
      suggested_quantity: row.suggested_quantity,
      source: source && { vendor_name: source.vendor_name.presence, vendor_part_number: source.vendor_part_number.presence,
                          url: source.url.presence || row.item.url.presence }
    }
  end
end
