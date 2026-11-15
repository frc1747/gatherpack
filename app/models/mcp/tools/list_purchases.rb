# Vendor orders the viewer can see, as the purchases list shows them
# (Orders::PurchasesController#index: policy_scope(Purchase), newest order date first, mine
# for the viewer's own). PurchasePolicy#full? decides what each row shows: buyers, admins and
# those reaching every request on it get the order number, buyer and total; anyone who sees it
# only through a request gets the vendor, dates and the status of their own items. Needs the
# orders feature.
class Mcp::Tools::ListPurchases < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "list_purchases"
  description "Vendor orders you can see, newest first. Buyers and those over all of an order's requests see its order " \
    "number, buyer and total (full: true); others see the vendor, dates and the status of their own items. mine: only orders " \
    "you placed."
  scope :read
  feature :orders
  input_schema(
    properties: {
      mine: { type: "boolean", description: "Only orders you placed (default false)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::OrderRecords::PURCHASE_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(mine: false, limit: DEFAULT_LIMIT)
    purchases = ctx.policy_scope(Purchase).includes(:vendor, :buyer, order_lines: :order_request)
      .order(Purchase.arel_table[:ordered_on].desc.nulls_last, created_at: :desc, id: :asc)
    purchases = purchases.where(buyer: ctx.person) if mine
    list(purchases, limit: limit) { |purchase| purchase_json(purchase) }
  end
end
