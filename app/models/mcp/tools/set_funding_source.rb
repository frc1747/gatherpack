# Sets where a request's or one item's money comes from, as the pages that set it do.
#
# A request (order_request_id): the approver's picker and the request form's Paid from
# (Orders::DecisionsController, Orders::RequestsController#update). Found in
# policy_scope(OrderRequest) and asked show? and set_funding? (approvers who can decide it, and
# requesters while orders_requesters_pick_funding is on), then OrderRequest#edit!, which checks it
# again and records it in the timeline. The source must be in use, or the request's own already.
#
# An item (order_line_id): before it's bought, the approver's item edit
# (Orders::LineEditsController: the item on a request in policy_scope(OrderRequest),
# approver_edit? and set_funding?, then edit_line!); once it's bought, a funding manager's
# reallocation (Orders::ReallocationsController, which finds the item without the request scope
# and asks only OrderLinePolicy#reallocate?, so a funding manager who can't open the request can
# still move it; anyone else gets "Not found"), then reallocate_funding! with a required reason.
# funding_source_report gives the items' IDs. funding_source_id null clears the item's own
# source, so it's paid from the request's.
#
# A source the request's team can't use, and the actions' other refusals, come back as
# invalid-argument errors with the page's message. The result gives the request only to those
# who may open it (a funding manager may move an item on one they can't), and the item that was
# set with its funding source now. Needs the orders feature.
class Mcp::Tools::SetFundingSource < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "set_funding_source"
  description "Set where the money comes from: a request's funding source (approvers deciding it, and requesters where the " \
    "organization lets them pick), or one item's (approvers before it's bought; funding managers move a bought item, with a " \
    "reason; their IDs are in funding_source_report). Give order_request_id or order_line_id. Returns the request (null " \
    "when you can't open it) and the item set."
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
  output_schema(
    type: "object",
    properties: {
      order_request: { anyOf: [ Mcp::OrderRecords::REQUEST_SCHEMA, { type: "null" } ] },
      line: {
        anyOf: [
          { type: "object", properties: { id: { type: "string" }, description: { type: "string" }, funding_source: Mcp::OrderRecords::NULLABLE_REF },
            required: %w[id description funding_source] },
          { type: "null" }
        ]
      }
    },
    required: %w[order_request line]
  )

  def call(funding_source_id:, order_request_id: nil, order_line_id: nil, reason: nil)
    if order_request_id.present? == order_line_id.present?
      invalid_argument!("Give order_request_id or order_line_id, not both")
    end

    return { order_request: request_json(set_for_request(order_request_id, funding_source_id).reload), line: nil } if order_request_id

    line = set_for_line(order_line_id, funding_source_id, reason).reload
    visible = ctx.policy_scope(OrderRequest).exists?(id: line.order_request_id)
    {
      order_request: (request_json(line.order_request.reload) if visible),
      line: { id: line.neat_id, description: line.display_name, funding_source: line.funding_source && funding_ref_json(line.funding_source) }
    }
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

  def set_for_line(order_line_id, funding_source_id, reason)
    line = Mcp.find_by_neat_id(OrderLine, order_line_id)
    if line&.purchase_id
      not_found! unless ctx.allowed?(line, :reallocate?)
      source = funding_source_id && ctx.find(FundingSource, funding_source_id)
      order_action { line.reallocate_funding!(source, by: ctx.person, reason: reason) }
    else
      line = find_order_line(order_line_id)
      source = funding_source_id && ctx.find(FundingSource, funding_source_id)
      ctx.authorize!(line.order_request, :approver_edit?)
      ctx.authorize!(line.order_request, :set_funding?)
      order_action { line.order_request.edit_line!(line, { funding_source_id: source&.id }, by: ctx.person) }
    end
    changed!(line, line.order_request)
    line
  end
end
