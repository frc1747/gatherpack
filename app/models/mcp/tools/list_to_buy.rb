# The To buy queue (Orders::PurchasesController#to_buy): approved, unbought items within the
# viewer's buyer reach, grouped by vendor as Orders::ToBuy groups them ("Vendor not chosen"
# first, then by oldest needed-by). Only buyers: authorize Purchase, :create?, as the page. A
# vendor's account note shows where VendorPolicy#account_note? allows, as on the page. Record a
# purchase with record_purchase, taking items from one group. Needs the orders feature.
class Mcp::Tools::ListToBuy < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "list_to_buy"
  description "Your To buy queue: approved items waiting for a buyer within your reach, grouped by vendor (\"Vendor not " \
    "chosen\" first). Buyers only. Record a purchase of items from one group with record_purchase."
  scope :read
  feature :orders
  input_schema(properties: {})
  output_schema(
    type: "object",
    properties: {
      groups: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            kind: { type: "string", enum: %w[vendor other not_sure] },
            vendor: Mcp::OrderRecords::NULLABLE_REF,
            account_note: { type: %w[string null] },
            earliest_needed_by: { type: %w[string null] },
            total: Mcp::OrderRecords::MONEY_SCHEMA,
            items: {
              type: "array",
              items: {
                type: "object",
                properties: Mcp::OrderRecords::LINE_SCHEMA[:properties].merge(
                  order_request: Mcp::OrderRecords::REQUEST_REF_SCHEMA,
                  team: Mcp::Tool::REF_SCHEMA,
                  needed_by: { type: %w[string null] },
                  cost: Mcp::OrderRecords::MONEY_SCHEMA
                ),
                required: Mcp::OrderRecords::LINE_SCHEMA[:required] + %w[order_request team needed_by cost]
              }
            }
          },
          required: %w[name kind vendor account_note earliest_needed_by total items]
        }
      }
    },
    required: %w[groups]
  )

  def call
    ctx.authorize!(Purchase, :create?)
    { groups: Orders::ToBuy.new(ctx.person).groups.map { |group| group_json(group) } }
  end

  private

  def group_json(group)
    vendor = group.vendor if group.key == :vendor
    {
      name: group.name,
      kind: group.key.to_s,
      vendor: vendor && { id: vendor.neat_id, name: vendor.name },
      account_note: (vendor.account_note.presence if vendor && ctx.allowed?(vendor, :account_note?)),
      earliest_needed_by: date_json(group.earliest_needed_by),
      total: money_json(group.total_cents),
      items: group.lines.map do |line|
        line_json(line).merge(
          order_request: request_ref_json(line.order_request),
          team: team_json(line.order_request.team),
          needed_by: date_json(line.order_request.needed_by),
          cost: money_json(line.cost_cents)
        )
      end
    }
  end
end
