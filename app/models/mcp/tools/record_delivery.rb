# Records a delivery of an ordered item, as Receive does (Orders::DeliveriesController#create).
#
# Mirrors: the request is found in policy_scope(OrderRequest) and asked receive? (the
# requester, followers, team members who see it, buyers and managers), and the item on it. Then
# OrderLine#record_delivery! with quantity (default: what's still to come), date (default
# today), problem_kind_id (an active delivery problem; none means it arrived good) and note: good
# items count towards the quantity, a problem makes it one for its buyer, and the same notices go out. Its refusals come back as
# invalid-argument errors with the page's message.
#
# put_away is the receive dialog's Inventory section, run by the receiving extension
# (OrderInventory::PutAway) with the same params: where it goes, which inventory item it is (or
# create_item), and how many go into stock. Only a good delivery is put away, and only where both
# features are on; a put-away that can't be done is listed in put_away_problems while the delivery
# is still recorded, as the page's notice says. Needs the orders feature.
class Mcp::Tools::RecordDelivery < Mcp::Tool
  include Mcp::OrderRecords

  tool_name "record_delivery"
  description "Record a delivery of an ordered item, as Receive does: how many came (default: all still to come), when " \
    "(default today), a delivery problem if there was one (problem_kind_id, see list_order_lists; none means it arrived good) and a note. A problem goes to the buyer. " \
    "put_away also records good items into inventory, as the dialog's Inventory section does. Returns the delivery and the item."
  scope :write
  feature :orders
  input_schema(
    properties: {
      order_line_id: { type: "string", description: "The item's ID (ordl_)" },
      quantity: { type: "integer", minimum: 1, maximum: 1_000_000, description: "How many came (default: what's still to come)" },
      received_on: { type: "string", format: "date", description: "YYYY-MM-DD; default today" },
      problem_kind_id: { type: "string", description: "What was wrong: a delivery problem's ID (dpk_), key or name. Default: nothing, it arrived good" },
      note: { type: "string" },
      put_away: {
        type: "object",
        description: "Put good items away in inventory",
        properties: {
          location_id: { type: "string", description: "Where it goes (loc_)" },
          item_id: { type: "string", description: "The inventory item it is (itm_), for an order item not linked to one" },
          create_item: { type: "boolean", description: "Create an inventory item from it instead (inventory managers)" },
          quantity: { type: "integer", minimum: 1, maximum: 1_000_000, description: "How many go into stock, in pieces (default: what came)" }
        },
        required: %w[location_id],
        additionalProperties: false
      }
    },
    required: %w[order_line_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: {
      delivery: {
        type: "object",
        properties: { id: { type: "string" }, quantity: { type: "integer" }, condition: { type: "string", description: "Good, or the problem's name" },
                      problem_kind: { anyOf: [ Mcp::OrderRecords::PROBLEM_KIND_SCHEMA, { type: "null" } ] }, received_on: { type: "string" },
                      received_by: Mcp::Tool::REF_SCHEMA },
        required: %w[id quantity condition problem_kind received_on received_by]
      },
      line: Mcp::OrderRecords::LINE_SCHEMA,
      order_request: Mcp::OrderRecords::REQUEST_SCHEMA,
      put_away_problems: { type: "array", items: { type: "string" } }
    },
    required: %w[delivery line order_request put_away_problems]
  )

  def call(order_line_id:, quantity: nil, received_on: nil, problem_kind_id: nil, note: nil, put_away: nil)
    line = find_order_line(order_line_id)
    ctx.authorize!(line.order_request, :receive?)
    Orders::Lists.seed!
    problem_kind = active_list_row(DeliveryProblemKind.active, problem_kind_id, "problem_kind_id") if problem_kind_id.present?
    params = put_away ? put_away_params(put_away) : {}
    problems_before = OrderInventory::Current.problems.size
    delivery = order_action do
      line.record_delivery!(by: ctx.person, quantity: quantity || [ line.to_come_quantity, 1 ].max,
        received_on: parse_order_date(received_on, "received_on") || Date.current, problem_kind: problem_kind, note: note.presence, params: params)
    end
    line.reload
    changed!(delivery, line)
    {
      delivery: { id: delivery.neat_id, quantity: delivery.quantity, condition: delivery.condition_name,
                  problem_kind: (problem_kind_json(delivery.delivery_problem_kind) if delivery.delivery_problem_kind), received_on: date_json(delivery.received_on),
                  received_by: person_json(ctx.person) },
      line: line_json(line),
      order_request: request_json(line.order_request.reload),
      put_away_problems: OrderInventory::Current.problems.drop(problems_before)
    }
  end

  private

  # The dialog's fields, with the IDs it posts.
  def put_away_params(values)
    invalid_argument!("put_away needs inventory, which is turned off") unless OrderInventory.enabled?

    location = Mcp.find_by_neat_id(Location, values["location_id"]) || not_found!
    fields = { put_away: "1", location_id: location.id }
    fields[:item_id] = (Mcp.find_by_neat_id(Item, values["item_id"]) || not_found!).id if values["item_id"].present?
    fields[:create_item] = "1" if values["create_item"]
    fields[:quantity] = values["quantity"].to_s if values["quantity"]
    { order_inventory: fields }
  end
end
