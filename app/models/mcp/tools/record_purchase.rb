# Records a vendor order for items on the viewer's To buy list, as Record purchase does
# (Orders::PurchasesController#create).
#
# Mirrors: authorize Purchase, :create? (buyers); the items must all still be waiting for this
# buyer and come from one vendor (Orders::ToBuy#selection, with its messages). The vendor is the
# items' own; for "Not sure" items it's vendor_id (an active vendor) or other_vendor_name, as the
# page asks. A price left out keeps the estimate. paid_with must be one of orders_paid_with's
# choices, and one that reimburses sets the buyer to be paid back, as the page does. Then
# Orders::RecordPurchase, which locks the requests, puts the items on the purchase, tells the
# requesters, and sends items whose price rose past the tolerance back for re-approval (counted
# in needs_reapproval). Receipts and Record in ledger are left to the page. Needs the orders
# feature.
class Mcp::Tools::RecordPurchase < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "record_purchase"
  description "Record a vendor order for items on your To buy list (list_to_buy), all from one vendor: order number, order " \
    "date (default today), price each (default: the estimate), shipping, tax, paid with, expected date, tracking link and a " \
    "note. For \"Vendor not chosen\" items, say where they were bought (vendor_id or other_vendor_name). Buyers only. " \
    "Returns the order, and how many items now need re-approval because they cost more than was approved."
  scope :write
  feature :orders
  input_schema(
    properties: {
      lines: {
        type: "array", minItems: 1, maxItems: 100,
        items: {
          type: "object",
          properties: {
            id: { type: "string", description: "An item on your To buy list (ordl_)" },
            price_cents: { type: "integer", minimum: 0, maximum: 100_000_000, description: "Price paid each, in cents. Default: the estimate." }
          },
          required: %w[id],
          additionalProperties: false
        }
      },
      vendor_id: { type: "string", description: "For \"Vendor not chosen\" items: the vendor they were bought from (vnd_)" },
      other_vendor_name: { type: "string", description: "For \"Vendor not chosen\" items: another store's name" },
      vendor_order_number: { type: "string" },
      ordered_on: { type: "string", format: "date", description: "YYYY-MM-DD; default today" },
      expected_on: { type: "string", format: "date", description: "Expected delivery, YYYY-MM-DD" },
      tracking_url: { type: "string" },
      shipping_cents: { type: "integer", minimum: 0, maximum: 100_000_000 },
      tax_cents: { type: "integer", minimum: 0, maximum: 100_000_000 },
      paid_with: { type: "string", description: "One of the organization's paid-with choices (default the first)" },
      note: { type: "string" }
    },
    required: %w[lines],
    closed: true
  )
  output_schema(
    type: "object",
    properties: { purchase: Mcp::OrderRecords::PURCHASE_SCHEMA, needs_reapproval: { type: "integer" } },
    required: %w[purchase needs_reapproval]
  )

  def call(lines:, vendor_id: nil, other_vendor_name: nil, vendor_order_number: nil, ordered_on: nil, expected_on: nil,
    tracking_url: nil, shipping_cents: nil, tax_cents: nil, paid_with: nil, note: nil)
    ctx.authorize!(Purchase, :create?)
    chosen = lines.map { |line| [ Mcp.find_by_neat_id(OrderLine, line["id"]) || not_found!, line["price_cents"] ] }
    group = order_action { Orders::ToBuy.new(ctx.person).selection(chosen.map { |line, _| line.id }) }
    vendor, other_name = chosen_vendor(group, vendor_id, other_vendor_name)
    attributes = {
      vendor_order_number: vendor_order_number.presence,
      ordered_on: ordered_on ? parse_order_date(ordered_on, "ordered_on") : Date.current,
      expected_on: parse_order_date(expected_on, "expected_on"),
      tracking_url: tracking_url.presence,
      shipping_cents: shipping_cents.to_i,
      tax_cents: tax_cents.to_i,
      note: note.presence
    }.merge(payment(paid_with))
    prices = chosen.filter_map { |line, cents| [ line.id, cents ] unless cents.nil? }.to_h

    purchase = order_action do
      Orders::RecordPurchase.new(buyer: ctx.person, lines: group.lines, vendor: vendor, other_vendor_name: other_name,
        prices: prices, attributes: attributes).call
    end
    bought = purchase.order_lines.reload.to_a
    changed!(purchase, *bought)
    { purchase: purchase_json(purchase), needs_reapproval: bought.count(&:needs_reapproval?) }
  end

  private

  # The items' own vendor, or for "Not sure" items the one named here (PurchasesController#chosen_vendor).
  def chosen_vendor(group, vendor_id, other_vendor_name)
    case group.key
    when :vendor then [ group.vendor, nil ]
    when :other then [ nil, group.other_vendor_name ]
    else
      return [ ctx.find(ctx.policy_scope(Vendor).active, vendor_id), nil ] if vendor_id.present?

      invalid_argument!("Say where these items were bought: vendor_id or other_vendor_name") if other_vendor_name.blank?
      [ nil, other_vendor_name ]
    end
  end

  # paid_with and who to pay back, as the page sets them.
  def payment(label)
    choices = Orders::Config.paid_with
    choice = label.nil? ? choices.first : choices.find { |option| option.label == label }
    invalid_argument!("paid_with must be one of: #{choices.map(&:label).join(", ")}") if choice.nil?

    { paid_with: choice.label, reimburse_to_id: choice.reimburse ? ctx.person.id : nil }
  end
end
