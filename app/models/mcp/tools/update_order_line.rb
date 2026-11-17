# A buyer's change to one item after approval, as the item's Change menu does
# (Orders::BuyerLinesController): mark it delayed with an expected date, change its quantity,
# or cancel it with a reason.
#
# Mirrors: the item is found on a request in policy_scope(OrderRequest) and asked
# OrderLinePolicy#buy? (buyers within reach, the team's managers, admins). Then OrderLine's
# backorder!, change_quantity! (a raised quantity past the price tolerance sends the item back
# for re-approval, as the page's notice says) or cancel! (a reason is required), which write the
# timeline and send the notices. Their refusals come back as invalid-argument errors with the
# page's message. Comments and reasons stay out of the Rails log. Needs the orders feature.
class Mcp::Tools::UpdateOrderLine < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "update_order_line"
  description "A buyer's change to an approved item: backorder (delayed, with an optional expected date), change_quantity, " \
    "or cancel (with a reason). Buyers for the request's team only. Raising a quantity past the price tolerance sends the item " \
    "back for re-approval (needs_reapproval). Returns the item and its request."
  scope :write
  feature :orders
  input_schema(
    properties: {
      order_line_id: { type: "string", description: "The item's ID (ordl_)" },
      action: { type: "string", enum: %w[backorder change_quantity cancel] },
      expected_on: { type: "string", format: "date", description: "backorder: when it's now expected, YYYY-MM-DD" },
      quantity: { type: "integer", minimum: 1, maximum: 1_000_000, description: "change_quantity: the new quantity" },
      comment: { type: "string", description: "backorder, change_quantity: a note for the timeline" },
      reason: { type: "string", description: "cancel: why (required)" }
    },
    required: %w[order_line_id action],
    closed: true
  )
  output_schema(
    type: "object",
    properties: { line: Mcp::OrderRecords::LINE_SCHEMA, order_request: Mcp::OrderRecords::REQUEST_SCHEMA, needs_reapproval: { type: "boolean" } },
    required: %w[line order_request needs_reapproval]
  )

  def call(order_line_id:, action:, expected_on: nil, quantity: nil, comment: nil, reason: nil)
    line = find_order_line(order_line_id)
    ctx.authorize!(line, :buy?)
    by = ctx.person
    order_action do
      case action
      when "backorder" then line.backorder!(by: by, expected_on: parse_order_date(expected_on, "expected_on"), comment: comment)
      when "change_quantity"
        invalid_argument!("Give the new quantity") if quantity.nil?
        line.change_quantity!(quantity, by: by, comment: comment)
      when "cancel" then line.cancel!(by: by, reason: reason)
      end
    end
    line.reload
    changed!(line, line.order_request)
    { line: line_json(line), order_request: request_json(line.order_request.reload), needs_reapproval: line.needs_reapproval? }
  end
end
