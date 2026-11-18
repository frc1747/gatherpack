# The viewer's next steps in orders, as Home's To do and the My Orders card list them
# (Orders::WaitingOn#todos): requests to approve or re-approve, their own requests sent back
# for changes, problem deliveries on things they bought, and counts of items to buy and to
# receive. Rows with a request are kept only when the request is in policy_scope(OrderRequest),
# as the To approve page cross-checks them. Needs the orders feature.
class Mcp::Tools::OrdersWaitingOnMe < Mcp::Tool
  include Mcp::OrderRecords

  KINDS = %w[approve reapprove update buy resolve receive].freeze

  tool_name "orders_waiting_on_me"
  description "Your next steps in orders, soonest needed first: requests to approve or re-approve (approve, reapprove), " \
    "your requests sent back for changes with the approver's comment (update), problem deliveries on things you bought " \
    "(resolve), and how many items wait for you to buy (buy) or receive (receive)."
  scope :read
  feature :orders
  input_schema(properties: {})
  output_schema(
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            kind: { type: "string", enum: KINDS },
            order_request: { anyOf: [ Mcp::OrderRecords::REQUEST_REF_SCHEMA, { type: "null" } ] },
            count: { type: %w[integer null] },
            needed_by: { type: %w[string null] },
            comment: { type: %w[string null] }
          },
          required: %w[kind order_request count needed_by comment]
        }
      }
    },
    required: %w[items]
  )

  def call
    todos = Orders::WaitingOn.for(ctx.person).todos
    ids = todos.filter_map { |todo| todo.order_request&.id }
    visible = ctx.policy_scope(OrderRequest).where(id: ids).ids.to_set
    rows = todos.select { |todo| todo.order_request.nil? || visible.include?(todo.order_request.id) }
    {
      items: rows.map do |todo|
        {
          kind: todo.kind.to_s,
          order_request: todo.order_request && request_ref_json(todo.order_request),
          count: todo.count,
          needed_by: date_json(todo.needed_by),
          comment: todo.comment.presence
        }
      end
    }
  end
end
