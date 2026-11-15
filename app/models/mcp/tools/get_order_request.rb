# One order request as its page shows it to the viewer (Orders::RequestsController#show and
# the page's slots): its items, where they were ordered, its approvals, who follows it, and the
# timeline.
#
# Mirrors: set_order_request (policy_scope(OrderRequest), authorize show?), so a draft is its
# requester's alone. As the page: the total leaves out estimated shipping unless
# see_estimated_shipping?; the funding source (request's and items') shows only to those who
# see_funding?; the timeline leaves out following and, for those who don't see them, funding and
# shipping changes (OrderRequestsHelper#order_timeline_changes). decision is the approver's part
# (_decision): only for approvers of the request's team while a decision waits, with whether they
# may decide or why not, the restrictions of the sources it uses, and the flags. Needs the orders
# feature.
class Mcp::Tools::GetOrderRequest < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "get_order_request"
  description "One order request as its page shows it to you: items with status, store, part numbers and price, where they " \
    "were ordered, approvals, followers and the timeline. Approvers also get the decision waiting on them, the funding " \
    "restriction to confirm and what to check."
  scope :read
  feature :orders
  input_schema(
    properties: { order_request_id: { type: "string", description: "The request's ID (ordr_)" } },
    required: %w[order_request_id]
  )
  output_schema(
    type: "object",
    properties: Mcp::OrderRecords::REQUEST_SCHEMA[:properties].merge(
      purpose: { type: %w[string null] },
      funding_source: Mcp::OrderRecords::NULLABLE_REF,
      estimated_shipping: Mcp::OrderRecords::NULLABLE_MONEY,
      lines: { type: "array", items: Mcp::OrderRecords::LINE_SCHEMA },
      purchases: {
        type: "array",
        items: {
          type: "object",
          properties: { id: { type: "string" }, vendor_name: { type: %w[string null] }, items: { type: "integer" },
                        ordered_on: { type: %w[string null] }, expected_on: { type: %w[string null] }, status_text: { type: "string" } },
          required: %w[id vendor_name items ordered_on expected_on status_text]
        }
      },
      approvals: {
        type: "array",
        items: {
          type: "object",
          properties: { step: { type: "string" }, decision: { type: "string" }, by: Mcp::OrderRecords::NULLABLE_REF,
                        comment: { type: %w[string null] }, at: { type: "string" } },
          required: %w[step decision by comment at]
        }
      },
      followers: { type: "array", items: Mcp::Tool::REF_SCHEMA },
      timeline: {
        type: "array",
        items: {
          type: "object",
          properties: { action: { type: "string" }, text: { type: "string" }, item: { type: %w[string null] },
                        by: { type: "string" }, at: { type: "string" }, changes: { type: "array", items: { type: "string" } },
                        comment: { type: %w[string null] } },
          required: %w[action text item by at changes comment]
        }
      },
      decision: {
        anyOf: [
          {
            type: "object",
            properties: {
              step: { type: "string" },
              reapproval: { type: "boolean" },
              can_decide: { type: "boolean" },
              refusal: { type: %w[string null] },
              restrictions: {
                type: "array",
                items: { type: "object", properties: { funding_source: Mcp::Tool::REF_SCHEMA, restriction: { type: "string" } } }
              },
              flags: { type: "array", items: { type: "string" } }
            },
            required: %w[step reapproval can_decide refusal restrictions flags]
          },
          { type: "null" }
        ]
      }
    ),
    required: Mcp::OrderRecords::REQUEST_SCHEMA[:required] + %w[purpose lines purchases approvals followers timeline decision]
  )

  def call(order_request_id:)
    order_request = find_order_request(order_request_id)
    policy = order_words.policy(order_request)
    see_funding = policy.see_funding?
    request_json(order_request).merge(
      purpose: order_request.purpose.presence,
      funding_source: (funding_ref_json(order_request.funding_source) if see_funding && order_request.funding_source),
      estimated_shipping: (money_json(order_request.estimated_shipping_cents) if policy.see_estimated_shipping?),
      lines: order_request.order_lines.includes(:vendor, :funding_source, :item).map { |line| line_json(line, see_funding: see_funding) },
      purchases: purchases_json(order_request),
      approvals: order_request.active_approvals.map { |approval| approval_json(approval) },
      followers: order_request.order_request_watchers.includes(:person).map(&:person).sort_by { |person| person.identifier_name.to_s }
        .map { |person| person_json(person) },
      timeline: order_words.order_timeline_events(order_request).map { |event| event_json(event, order_request) },
      decision: decision_json(order_request)
    )
  end

  private

  # The page's "Ordered" section: each purchase holding this request's items.
  def purchases_json(order_request)
    lines = order_request.order_lines.reject(&:pending?)
    lines.filter_map(&:purchase).uniq.sort_by { |purchase| purchase.ordered_on || Date.new(0) }.map do |purchase|
      own = lines.select { |line| line.purchase_id == purchase.id }
      {
        id: purchase.neat_id,
        vendor_name: purchase.vendor_name,
        items: own.size,
        ordered_on: date_json(purchase.ordered_on),
        expected_on: date_json(purchase.expected_on),
        status_text: order_words.purchase_status_text(own)
      }
    end
  end

  def approval_json(approval)
    {
      step: approval.step_name.to_s,
      decision: approval.decision,
      by: approval.approver && person_json(approval.approver),
      comment: approval.comment.presence,
      at: time_json(approval.created_at)
    }
  end

  def event_json(event, order_request)
    {
      action: event.action,
      text: order_words.order_timeline_action(event),
      item: event.order_line&.display_name,
      by: event.actor&.identifier_name || "GatherPack",
      at: time_json(event.created_at),
      changes: order_words.order_timeline_changes(event, order_request),
      comment: event.comment.presence
    }
  end

  # Shown, as on the page, to approvers of the request's team while a decision waits.
  def decision_json(order_request)
    step = order_request.decision_step
    access = Orders::Access.for(ctx.person)
    return nil unless step && (access.approver_on?(step, order_request.team_id) || access.any_approver_team_ids.include?(order_request.team_id))

    flags = Orders::ApprovalFlags.new(order_request)
    {
      step: step.name,
      reapproval: !order_request.submitted?,
      can_decide: order_request.can_decide?(ctx.person),
      refusal: order_request.decision_refusal(ctx.person),
      restrictions: order_request.restricted_sources.map { |source| { funding_source: funding_ref_json(source), restriction: source.restriction.to_s } },
      flags: flags.request_flags.map(&:text) +
        order_request.live_lines.filter_map do |line|
          texts = flags.line_flags(line).map(&:text)
          "#{line.display_name}: #{texts.join(", ")}" if texts.any?
        end
    }
  end
end
