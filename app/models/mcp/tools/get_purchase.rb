# One vendor order as its page shows it (Orders::PurchasesController#show: policy_scope(Purchase),
# authorize show?). Those PurchasePolicy#full? allows get the order number, buyer, paid with,
# tracking, note, receipts (by name), every item with its price and cost, the totals, and the
# shipping and tax split by request when it covers more than one. Anyone else gets the vendor,
# dates, status and their own items (PurchasePolicy#visible_lines), without prices. Needs the
# orders feature.
class Mcp::Tools::GetPurchase < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "get_purchase"
  description "One vendor order as its page shows it to you. Buyers and those over all its requests see the order number, " \
    "buyer, payment, tracking, receipts, prices and totals; others see the vendor, dates, status and their own items."
  scope :read
  feature :orders
  input_schema(
    properties: { purchase_id: { type: "string", description: "The order's ID (pur_)" } },
    required: %w[purchase_id]
  )
  output_schema(
    type: "object",
    properties: Mcp::OrderRecords::PURCHASE_SCHEMA[:properties].merge(
      paid_with: { type: %w[string null] },
      reimburse_to: Mcp::OrderRecords::NULLABLE_REF,
      tracking_url: { type: %w[string null] },
      note: { type: %w[string null] },
      receipts: { type: "array", items: { type: "string" } },
      lines: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" }, description: { type: "string" }, order_request: Mcp::OrderRecords::REQUEST_REF_SCHEMA,
            quantity: { type: "integer" }, status: { type: "string" }, status_text: { type: "string" },
            expected_on: { type: %w[string null] }, unit_price: Mcp::OrderRecords::NULLABLE_MONEY, cost: Mcp::OrderRecords::NULLABLE_MONEY
          },
          required: %w[id description order_request quantity status status_text]
        }
      },
      totals: {
        anyOf: [
          {
            type: "object",
            properties: { items: Mcp::OrderRecords::MONEY_SCHEMA, shipping: Mcp::OrderRecords::MONEY_SCHEMA,
                          tax: Mcp::OrderRecords::MONEY_SCHEMA, total: Mcp::OrderRecords::MONEY_SCHEMA },
            required: %w[items shipping tax total]
          },
          { type: "null" }
        ]
      },
      by_request: {
        type: "array",
        items: {
          type: "object",
          properties: { order_request: Mcp::OrderRecords::REQUEST_REF_SCHEMA, items: Mcp::OrderRecords::MONEY_SCHEMA,
                        shipping_and_tax: Mcp::OrderRecords::MONEY_SCHEMA, total: Mcp::OrderRecords::MONEY_SCHEMA },
          required: %w[order_request items shipping_and_tax total]
        }
      }
    ),
    required: Mcp::OrderRecords::PURCHASE_SCHEMA[:required] + %w[lines totals by_request]
  )

  def call(purchase_id:)
    purchase = ctx.find(ctx.policy_scope(Purchase).includes(:vendor, :buyer, order_lines: [ :vendor, { order_request: :team } ]), purchase_id)
    ctx.authorize!(purchase, :show?)
    policy = order_words.policy(purchase)
    full = policy.full?
    lines = policy.visible_lines.sort_by { |line| [ line.order_request.display_title, line.position.to_i ] }
    json = purchase_json(purchase).merge(
      lines: lines.map { |line| purchase_line_json(line, full) },
      totals: (totals_json(purchase) if full),
      by_request: full ? by_request_json(purchase) : []
    )
    return json unless full

    json.merge(
      paid_with: purchase.paid_with.presence,
      reimburse_to: (person_json(purchase.reimburse_to) if purchase.reimburse? && purchase.reimburse_to),
      tracking_url: purchase.tracking_url.presence,
      note: purchase.note.presence,
      receipts: purchase.receipts.map { |receipt| receipt.filename.to_s }
    )
  end

  private

  def purchase_line_json(line, full)
    json = {
      id: line.neat_id,
      description: line.display_name,
      order_request: request_ref_json(line.order_request),
      quantity: line.quantity,
      status: line.status,
      status_text: order_words.order_line_status_text(line),
      expected_on: (date_json(line.expected_on) if line.backordered?)
    }
    full ? json.merge(unit_price: money_json(line.unit_price_cents), cost: money_json(line.cost_cents)) : json
  end

  def totals_json(purchase)
    {
      items: money_json(purchase.lines_cost_cents),
      shipping: money_json(purchase.shipping_cents.to_i),
      tax: money_json(purchase.tax_cents.to_i),
      total: money_json(purchase.total_cents)
    }
  end

  # The page's "Shipping and tax by request", shown when there's some and more than one request.
  def by_request_json(purchase)
    return [] unless purchase.extras_cents.positive? && purchase.order_requests.size > 1

    requests = purchase.order_requests.index_by(&:id)
    Orders::PurchaseSplit.new(purchase).by_request.filter_map do |request_id, total|
      next unless requests[request_id]

      { order_request: request_ref_json(requests[request_id]), items: money_json(total.cost_cents),
        shipping_and_tax: money_json(total.extras_cents), total: money_json(total.total_cents) }
    end
  end
end
