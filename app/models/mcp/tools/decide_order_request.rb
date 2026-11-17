# Approves, asks for changes on, or declines an order request, as the request page's decision
# does (Orders::DecisionsController#create).
#
# Mirrors: the request is found in policy_scope(OrderRequest) and asked show?; then
# OrderRequest#decision_refusal, whose reason (your own request, a relative's, not an approver
# on this step, nothing waiting) comes back as "Not allowed" with it. A funding_source_id is the
# page's picker: used only while the request has none (otherwise ignored, as the page ignores
# it), among active sources, set through edit!, and kept even if the decision is then refused,
# as the page keeps it. Then decide!, which asks
# for a comment to ask for changes or decline, fits_restriction to approve a request using a
# restricted source, a funding source before the final approval where the organization requires
# one, and sends the same notices. Its refusals come back as invalid-argument errors with the
# page's message. Comments go to the requester and stay out of the Rails log. Needs the orders
# feature.
class Mcp::Tools::DecideOrderRequest < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "decide_order_request"
  description "Approve, ask for changes on, or decline an order request waiting on you, with a comment (required to ask for " \
    "changes or decline), as the request page's decision does. Approving a request paid from a restricted source needs " \
    "fits_restriction: true, after checking get_order_request's restriction. funding_source_id sets the source when the " \
    "request has none, and is ignored when it has one. You can't decide your own or a relative's request. Returns the request."
  scope :write
  feature :orders
  input_schema(
    properties: {
      order_request_id: { type: "string", description: "The request's ID (ordr_)" },
      decision: { type: "string", enum: %w[approve ask_for_changes decline] },
      comment: { type: "string", description: "Shown to the requester; required to ask for changes or decline" },
      fits_restriction: { type: "boolean", description: "This request fits the funding source's restriction (default false)" },
      funding_source_id: { type: "string", description: "Paid from (fund_), when the request has no funding source yet" }
    },
    required: %w[order_request_id decision],
    closed: true
  )
  output_schema(Mcp::OrderRecords::REQUEST_SCHEMA)

  DECISIONS = { "approve" => :approved, "ask_for_changes" => :changes_requested, "decline" => :declined }.freeze

  def call(order_request_id:, decision:, comment: nil, fits_restriction: false, funding_source_id: nil)
    order_request = find_order_request(order_request_id)
    refusal = order_request.decision_refusal(ctx.person)
    raise Mcp::NotAllowed, "Not allowed: #{refusal}" if refusal

    set_funding_source(order_request, funding_source_id) if funding_source_id
    order_action do
      order_request.decide!(DECISIONS.fetch(decision), by: ctx.person, comment: comment, fits_restriction: fits_restriction)
    end
    order_request.reload
    changed!(order_request, *order_request.order_approvals.last(1))
    request_json(order_request)
  end

  private

  # The page's picker, shown only while the request has no source.
  def set_funding_source(order_request, funding_source_id)
    return if order_request.funding_source_id.present?

    source = ctx.find(ctx.policy_scope(FundingSource).active, funding_source_id)
    order_action { order_request.edit!({ funding_source_id: source.id }, by: ctx.person) }
  end
end
