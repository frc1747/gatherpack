# Sets where a request's or one item's money comes from, as the pages that set it do.
#
# A request (order_request_id): the approver's picker and the request form's Paid from
# (Orders::DecisionsController, Orders::RequestsController#update). Found in
# policy_scope(OrderRequest) and asked show? and set_funding? (approvers who can decide it, and
# requesters while orders_requesters_pick_funding is on), then OrderRequest#edit!, which checks it
# again and records it in the timeline. The source must be in use, or the request's own already.
#
# An item (order_line_id): before it's bought, the approver's item edit
# (Orders::LineEditsController: approver_edit? and set_funding?, then edit_line!); once it's
# bought, a funding manager's reallocation (Orders::ReallocationsController: OrderLinePolicy
# reallocate?, then reallocate_funding! with a required reason). funding_source_id null clears
# the item's own source, so it's paid from the request's.
#
# A source the request's team can't use, and the actions' other refusals, come back as
# invalid-argument errors with the page's message. Needs the orders feature.
class Mcp::Tools::SetFundingSource < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "set_funding_source"
  description "Set where the money comes from: a request's funding source (approvers deciding it, and requesters where the " \
    "organization lets them pick), or one item's (approvers before it's bought; funding managers move a bought item, with a " \
    "reason). Give order_request_id or order_line_id. Returns the request."
  scope :write
  feature :orders
  input_schema(
    properties: {
      order_request_id: { type: "string", description: "The request's ID (ordr_)" },
      order_line_id: { type: "string", description: "Or one item's ID (ordl_)" },
      funding_source_id: { type: %w[string null], description: "The funding source (fund_); for an item, null pays it from the request's source" },
      reason: { type: "string", description: "Why, when moving a bought item (required then)" }
    },
    required: %w[funding_source_id],
    closed: true
  )
  output_schema(Mcp::OrderRecords::REQUEST_SCHEMA)

  def call(funding_source_id:, order_request_id: nil, order_line_id: nil, reason: nil)
    if order_request_id.present? == order_line_id.present?
      invalid_argument!("Give order_request_id or order_line_id, not both")
    end

    order_request = order_line_id ? set_for_line(find_order_line(order_line_id), funding_source_id, reason) : set_for_request(order_request_id, funding_source_id)
    request_json(order_request.reload)
  end

  private

  def set_for_request(order_request_id, funding_source_id)
    order_request = find_order_request(order_request_id)
    ctx.authorize!(order_request, :set_funding?)
    invalid_argument!("Give the funding source to pay this request from") if funding_source_id.nil?

    source = ctx.find(FundingSource, funding_source_id)
    invalid_argument!("#{source.name} isn't in use") unless source.active? || source.id == order_request.funding_source_id
    order_action { order_request.edit!({ funding_source_id: source.id }, by: ctx.person) }
    changed!(order_request)
    order_request
  end

  def set_for_line(line, funding_source_id, reason)
    source = funding_source_id && ctx.find(FundingSource, funding_source_id)
    if line.purchase_id
      ctx.authorize!(line, :reallocate?)
      order_action { line.reallocate_funding!(source, by: ctx.person, reason: reason) }
    else
      ctx.authorize!(line.order_request, :approver_edit?)
      ctx.authorize!(line.order_request, :set_funding?)
      order_action { line.order_request.edit_line!(line, { funding_source_id: source&.id }, by: ctx.person) }
    end
    changed!(line, line.order_request)
    line.order_request
  end
end
