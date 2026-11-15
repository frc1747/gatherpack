# One funding source's report (Orders::FundingSourcesController#report: policy_scope(FundingSource),
# authorize report?, which is FundingSourcePolicy#numbers?): its amount, spent, committed and
# remaining, and every bought item charged to it (Orders::FundingReport) with its ID (for
# set_funding_source's reallocation), date, store, request, approver, cost and its share of
# shipping and tax, and the purchase's receipts by name. Someone who may see the source but not its numbers is "Not allowed". Needs the orders
# feature.
class Mcp::Tools::FundingSourceReport < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "funding_source_report"
  description "A funding source's report: amount, spent, committed and remaining, and every bought item charged to it with " \
    "date, store, request, approver, cost and share of shipping and tax. Funding managers, admins and approvers who can use " \
    "the source only."
  scope :read
  feature :orders
  input_schema(
    properties: { funding_source_id: { type: "string", description: "The source's ID (fund_)" } },
    required: %w[funding_source_id]
  )
  output_schema(
    type: "object",
    properties: {
      funding_source: Mcp::OrderRecords::FUNDING_SOURCE_SCHEMA,
      rows: {
        type: "array",
        items: {
          type: "object",
          properties: {
            order_line_id: { type: "string" }, date: { type: %w[string null] }, item: { type: "string" }, quantity: { type: "integer" }, store: { type: "string" },
            order_request: Mcp::OrderRecords::REQUEST_REF_SCHEMA, approved_by: { type: %w[string null] },
            cost: Mcp::OrderRecords::MONEY_SCHEMA, shipping_and_tax: Mcp::OrderRecords::MONEY_SCHEMA, total: Mcp::OrderRecords::MONEY_SCHEMA,
            receipts: { type: "array", items: { type: "string" } }
          },
          required: %w[order_line_id date item quantity store order_request approved_by cost shipping_and_tax total receipts]
        }
      },
      total: Mcp::OrderRecords::MONEY_SCHEMA
    },
    required: %w[funding_source rows total]
  )

  def call(funding_source_id:)
    source = ctx.find(FundingSource, funding_source_id)
    ctx.authorize!(source, :report?)
    report = Orders::FundingReport.new(source)
    {
      funding_source: funding_source_json(source),
      rows: report.rows.map { |row| row_json(row) },
      total: money_json(report.total_cents)
    }
  end

  private

  def row_json(row)
    {
      order_line_id: row.line.neat_id,
      date: date_json(row.date),
      item: row.item,
      quantity: row.line.quantity,
      store: row.vendor_name,
      order_request: request_ref_json(row.request),
      approved_by: row.approver&.display_name,
      cost: money_json(row.cost_cents),
      shipping_and_tax: money_json(row.extras_cents),
      total: money_json(row.total_cents),
      receipts: row.receipts.map { |receipt| receipt.filename.to_s }
    }
  end
end
