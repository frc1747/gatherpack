# The order requests the viewer can see, as Purchasing → Orders lists them
# (Orders::RequestsController#index: policy_scope(OrderRequest), most recently changed first).
# mine is My requests (their own and those they follow, as mine=1); waiting_on_me keeps the
# requests on the viewer's Home To do and To approve (Orders::WaitingOn#todos), cross-checked
# against the same scope as the To approve page. The total leaves out estimated shipping for
# those who don't see it. Needs the orders feature.
class Mcp::Tools::ListOrderRequests < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "list_order_requests"
  description "Order requests you can see, most recently changed first, with status, team, requester, needed-by and total. " \
    "Filters: status, team_id, mine (your own and those you follow), waiting_on_me (waiting for you to approve, update, " \
    "resolve or receive)."
  scope :read
  feature :orders
  input_schema(
    properties: {
      status: { type: "string", enum: Mcp::OrderRecords::REQUEST_STATUSES, description: "Only requests in this status" },
      team_id: { type: "string", description: "Only requests for this team (tm_)" },
      mine: { type: "boolean", description: "Only your own requests and those you follow (default false)" },
      waiting_on_me: { type: "boolean", description: "Only requests waiting on you (default false)" },
      limit: limit_property
    }
  )
  output_schema(
    type: "object",
    properties: { items: { type: "array", items: Mcp::OrderRecords::REQUEST_SCHEMA }, truncated: { type: "boolean" } },
    required: %w[items truncated]
  )

  def call(status: nil, team_id: nil, mine: false, waiting_on_me: false, limit: DEFAULT_LIMIT)
    requests = ctx.policy_scope(OrderRequest).includes(:team, :requested_by, :order_lines).order(updated_at: :desc, id: :asc)
    requests = requests.where(status: status) if status
    requests = requests.where(team_id: ctx.find(Team, team_id).id) if team_id
    if mine
      requests = requests.where(requested_by: ctx.person)
        .or(requests.where(id: OrderRequestWatcher.where(person: ctx.person).select(:order_request_id)))
    end
    requests = requests.where(id: waiting_ids) if waiting_on_me
    list(requests, limit: limit) { |order_request| request_json(order_request) }
  end

  private

  def waiting_ids
    Orders::WaitingOn.for(ctx.person).todos.filter_map { |todo| todo.order_request&.id }
  end
end
