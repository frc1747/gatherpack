require "test_helper"
require_relative "../../../support/mcp_orders_world"

# The orders write tools do what the pages do, through the same domain actions, and refuse
# whom and what the pages refuse.
class Mcp::Tools::OrderWritesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpOrdersWorld

  def approved_bought(lines = [ { description: "Bearing", price: 3, quantity: 4 } ])
    order_request = approved_request(@world, lines: lines)
    buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
    order_request.reload
  end

  test "create_order_request makes a request with the form's items and sends it for approval" do
    result = call_as(@world.requester, "create_order_request", purpose: "Practice field", needed_by: "2030-01-15",
      lines: [ { url: "https://partsdepot.example/p/SCR-4", quantity: 3, store: @world.preferred_vendor.neat_id, estimated_unit_price: "1.50" },
               { description: "Zip ties", store: "other", other_vendor_name: "Corner Store" },
               { description: "Hex key" } ])
    assert_nil result.error
    order_request = OrderRequest.find_by_neat_id(result.value["id"])

    assert_predicate order_request, :submitted?
    assert_equal @world.robotics, order_request.team
    assert_equal Date.new(2030, 1, 15), order_request.needed_by
    assert_equal [ :vendor, :other, :not_sure ], order_request.order_lines.map(&:vendor_choice)
    assert_equal [ 150, 3 ], order_request.order_lines.first.then { |line| [ line.estimated_unit_price_cents, line.quantity ] }
    assert_equal "partsdepot.example", order_request.title, "a blank title takes the first item's, as on submit"
    assert_equal %w[submitted], order_request.events.map(&:action)
    assert_equal [ order_request.neat_id ], call_as(@world.mentor, "list_order_requests", waiting_on_me: true).value["items"].map { |item| item["id"] }
  end

  test "create_order_request keeps a draft with submit false, and saves nothing it refuses" do
    draft = call_as(@world.requester, "create_order_request", submit: false, lines: [ { description: "Wheel" } ])
    assert_equal "draft", draft.value["status"]

    count = OrderRequest.count
    assert_match "Add an item", call_as(@world.requester, "create_order_request", lines: [ { quantity: 2 } ]).error
    assert_match "Item 1", call_as(@world.requester, "create_order_request", lines: [ { description: "Wheel", url: "javascript:alert(1)" } ]).error
    assert_equal count, OrderRequest.count

    with_orders_settings(orders_require_other_vendor_reason: "true") do
      result = call_as(@world.requester, "create_order_request", lines: [ { description: "Paint", store: "other", other_vendor_name: "Corner Store" } ])
      assert_not_nil result.error
    end
    assert_equal count, OrderRequest.count
  end

  test "create_order_request is refused to those New request refuses, and for a funding source they can't set" do
    source = FundingSource.create!(team: @world.club, name: "Build budget", kind: :general, active: true)
    count = OrderRequest.count

    with_orders_settings(orders_requesters: @world.robotics.name) do
      assert_equal "Not allowed", call_as(@world.outsider, "create_order_request", lines: [ { description: "Paint" } ]).error
    end
    assert_nil call_as(@world.requester, "create_order_request", team_id: @world.robotics.neat_id, lines: [ { description: "Paint" } ]).error
    assert_not_nil call_as(@world.requester, "create_order_request", team_id: @world.art.neat_id, lines: [ { description: "Paint" } ]).error
    assert_not_nil call_as(@world.requester, "create_order_request", funding_source_id: source.neat_id, lines: [ { description: "Paint" } ]).error
    assert_equal count + 1, OrderRequest.count

    with_orders_settings(orders_requesters_pick_funding: "true") do
      result = call_as(@world.requester, "create_order_request", funding_source_id: source.neat_id, lines: [ { description: "Paint" } ])
      assert_nil result.error
      assert_equal source, OrderRequest.find_by_neat_id(result.value["id"]).funding_source
    end
  end

  test "create_order_request links an inventory item the requester can see" do
    result = call_as(@world.requester, "create_order_request", lines: [ { description: "Screws", linked_item_id: @stock.screws.neat_id } ])
    assert_nil result.error
    assert_equal @stock.screws, OrderRequest.find_by_neat_id(result.value["id"]).order_lines.first.item

    art_item = Item.create!(team: @world.art, name: "Brushes")
    assert_equal "Not found", call_as(@world.requester, "create_order_request", lines: [ { description: "Brushes", linked_item_id: art_item.neat_id } ]).error
  end

  test "decide_order_request decides as the request page does, and refuses the requester and relatives" do
    order_request = submitted_request(@world)

    assert_equal "Not allowed: A relative made this request, so another approver has to decide.",
      call_as(@world.parent, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve").error
    assert_equal "Not allowed: You made this request, so another approver has to decide.",
      call_as(@world.requester, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve").error
    assert_equal "Not found", call_as(@world.outsider, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve").error
    assert_equal "Say what needs changing or why it's declined.",
      call_as(@world.mentor, "decide_order_request", order_request_id: order_request.neat_id, decision: "decline").error

    result = call_as(@world.mentor, "decide_order_request", order_request_id: order_request.neat_id, decision: "ask_for_changes",
      comment: "Which size?")
    assert_equal "changes_requested", result.value["status"]
    assert_equal [ "changes_requested", "Which size?" ], order_request.events.reload.last.then { |event| [ event.action, event.comment ] }

    order_request.resubmit!(by: @world.requester)
    assert_equal "approved", call_as(@world.mentor, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve").value["status"]
  end

  test "decide_order_request needs the restriction tick for a restricted source, and sets a source from the picker" do
    gift = FundingSource.create!(team: @world.club, name: "Gift", kind: :restricted, restriction: "Robot parts only", active: true)
    order_request = submitted_request(@world)

    refused = call_as(@world.mentor, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve",
      funding_source_id: gift.neat_id)
    assert_equal "Confirm the request fits the funding restriction.", refused.error
    assert_equal gift, order_request.reload.funding_source, "the picked source is kept, as the page keeps it"
    assert_predicate order_request, :submitted?

    result = call_as(@world.mentor, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve", fits_restriction: true)
    assert_equal "approved", result.value["status"]
    assert_equal true, order_request.events.reload.find_by(action: "approved").field_changes["fits_restriction"]
  end

  test "decide_order_request ignores the picker when the request already has a funding source, as the page does" do
    budget = FundingSource.create!(team: @world.club, name: "Build budget", kind: :general, active: true)
    other = FundingSource.create!(team: @world.club, name: "Spare", kind: :general, active: true)
    order_request = submitted_request(@world)
    order_request.edit!({ funding_source_id: budget.id }, by: @world.mentor)

    result = call_as(@world.mentor, "decide_order_request", order_request_id: order_request.neat_id, decision: "approve",
      funding_source_id: other.neat_id)
    assert_nil result.error
    assert_equal "approved", result.value["status"]
    assert_equal budget, order_request.reload.funding_source

    page_request = submitted_request(@world)
    page_request.edit!({ funding_source_id: budget.id }, by: @world.mentor)
    sign_in @world.mentor.user
    post orders_request_decisions_path(page_request), params: { decision: "approved", funding_source_id: other.id }
    assert_equal [ "approved", budget ], page_request.reload.then { |r| [ r.status, r.funding_source ] }, "the page does the same"
  end

  test "record_purchase records a buyer's order for To buy items, as Record purchase does" do
    order_request = approved_request(@world, lines: [ { description: "Bearing", price: 3, quantity: 4, vendor_id: @world.preferred_vendor.id },
      { description: "Belt", price: 9, vendor_id: @world.preferred_vendor.id }, { description: "Mystery", price: 1 } ])
    bearing, belt, mystery = order_request.order_lines.to_a

    assert_equal "Not allowed", call_as(@world.requester, "record_purchase", lines: [ { id: bearing.neat_id } ]).error
    assert_equal "Tick items from one vendor.", call_as(@world.buyer, "record_purchase", lines: [ { id: bearing.neat_id }, { id: mystery.neat_id } ]).error
    assert_match "Say where", call_as(@world.buyer, "record_purchase", lines: [ { id: mystery.neat_id } ]).error
    assert_match "payment_method_id must be one of: Team card, Paid personally",
      call_as(@world.buyer, "record_purchase", lines: [ { id: belt.neat_id } ], payment_method_id: "Cash").error
    personal = PaymentMethod.find_by!(name: "Paid personally")

    result = call_as(@world.buyer, "record_purchase", lines: [ { id: bearing.neat_id, price_cents: 350 }, { id: belt.neat_id } ],
      vendor_order_number: "PD-77", shipping_cents: 400, tax_cents: 100, payment_method_id: personal.neat_id)
    assert_nil result.error
    purchase = Purchase.find_by_neat_id(result.value["purchase"]["id"])
    assert_equal [ "PD-77", @world.preferred_vendor, @world.buyer, @world.buyer ], [ purchase.vendor_order_number, purchase.vendor, purchase.buyer, purchase.reimburse_to ]
    assert_equal personal, purchase.payment_method
    assert_equal [ 350, 900 ], [ bearing.reload.actual_unit_price_cents, belt.reload.actual_unit_price_cents ]
    assert_equal %w[ordered ordered], [ bearing.status, belt.status ]
    assert_equal 0, result.value["needs_reapproval"]
    assert_equal "Some of those items are no longer waiting for a buyer.", call_as(@world.buyer, "record_purchase", lines: [ { id: belt.neat_id } ]).error

    other = call_as(@world.buyer, "record_purchase", lines: [ { id: mystery.neat_id } ], other_vendor_name: "Corner Store")
    assert_equal "Corner Store", other.value["purchase"]["vendor_name"]
    assert_equal PaymentMethod.active.ordered.first, other.then { |result| Purchase.find_by_neat_id(result.value["purchase"]["id"]).payment_method },
      "the first active method when none is named"
    assert_equal "Corner Store", mystery.reload.purchase.other_vendor_name
  end

  test "update_order_line backorders, changes quantity and cancels for buyers only" do
    order_request = approved_bought([ { description: "Bearing", price: 3, quantity: 4 }, { description: "Belt", price: 9 } ])
    bearing, belt = order_request.order_lines.to_a

    assert_equal "Not allowed", call_as(@world.teammate, "update_order_line", order_line_id: bearing.neat_id, action: "cancel", reason: "No").error
    assert_equal "Not found", call_as(@world.outsider, "update_order_line", order_line_id: bearing.neat_id, action: "cancel", reason: "No").error

    result = call_as(@world.buyer, "update_order_line", order_line_id: bearing.neat_id, action: "backorder", expected_on: "2030-02-01")
    assert_equal [ "backordered", "2030-02-01" ], [ result.value["line"]["status"], result.value["line"]["expected_on"] ]

    assert_equal "Give a reason for cancelling.", call_as(@world.buyer, "update_order_line", order_line_id: belt.neat_id, action: "cancel").error
    assert_equal "cancelled", call_as(@world.manager, "update_order_line", order_line_id: belt.neat_id, action: "cancel", reason: "Out of stock").value["line"]["status"]

    changed = call_as(@world.buyer, "update_order_line", order_line_id: bearing.neat_id, action: "change_quantity", quantity: 2)
    assert_equal [ 2, false ], [ changed.value["line"]["quantity"], changed.value["needs_reapproval"] ]
    raised = call_as(@world.buyer, "update_order_line", order_line_id: bearing.neat_id, action: "change_quantity", quantity: 40)
    assert_equal true, raised.value["needs_reapproval"]
  end

  test "record_delivery records what came for those who may receive, and puts it away as the dialog does" do
    order_request = approved_request(@world, lines: [ { description: "M4 screw", price: 1, quantity: 10, item_type: "Item", item_id: @stock.screws.id } ])
    buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
    line = order_request.order_lines.first

    assert_equal "Not found", call_as(@world.outsider, "record_delivery", order_line_id: line.neat_id).error

    result = call_as(@world.requester, "record_delivery", order_line_id: line.neat_id, quantity: 6,
      put_away: { location_id: @stock.bin.neat_id })
    assert_nil result.error
    assert_equal [ "partly_received", [] ], [ result.value["line"]["status"], result.value["put_away_problems"] ]
    assert_equal 6, @stock.screws.stock_at(@stock.bin)

    damaged = call_as(@world.teammate, "record_delivery", order_line_id: line.neat_id, problem_kind_id: "Damaged", note: "Bent")
    assert_equal [ 4, "problem", "Damaged" ], [ damaged.value["delivery"]["quantity"], damaged.value["line"]["status"], damaged.value["delivery"]["problem_kind"]["name"] ]
    assert_equal DeliveryProblemKind.find_by!(key: "damaged"), OrderDelivery.find_by_neat_id(damaged.value["delivery"]["id"]).delivery_problem_kind
    assert_equal "This item isn't waiting to be received.",
      call_as(@world.requester, "record_delivery", order_line_id: approved_request(@world).order_lines.first.neat_id).error
  end

  test "record_delivery reports a put-away that couldn't be done and still records the delivery" do
    order_request = approved_bought([ { description: "Paint", price: 2 } ])
    line = order_request.order_lines.first
    result = call_as(@world.requester, "record_delivery", order_line_id: line.neat_id, put_away: { location_id: @stock.art_room.neat_id })
    assert_equal "received", result.value["line"]["status"]
    assert_equal 1, result.value["put_away_problems"].size
  end

  test "set_funding_source sets a request's source for approvers, and moves a bought item for funding managers" do
    budget = FundingSource.create!(team: @world.club, name: "Build budget", kind: :general, active: true)
    other = FundingSource.create!(team: @world.club, name: "Spare", kind: :general, active: true)
    order_request = submitted_request(@world)

    assert_equal "Not allowed", call_as(@world.requester, "set_funding_source", order_request_id: order_request.neat_id, funding_source_id: budget.neat_id).error
    result = call_as(@world.mentor, "set_funding_source", order_request_id: order_request.neat_id, funding_source_id: budget.neat_id)
    assert_nil result.error
    assert_equal budget, order_request.reload.funding_source

    line = order_request.order_lines.first
    assert_nil call_as(@world.mentor, "set_funding_source", order_line_id: line.neat_id, funding_source_id: other.neat_id).error
    assert_equal other, line.reload.funding_source

    bought = approved_bought.order_lines.first
    assert_equal "Not found", call_as(@world.mentor, "set_funding_source", order_line_id: bought.neat_id, funding_source_id: other.neat_id, reason: "Gift").error
    assert_equal "Give a reason for moving it.", call_as(@world.funding_manager, "set_funding_source", order_line_id: bought.neat_id, funding_source_id: other.neat_id).error
    assert_nil call_as(@world.funding_manager, "set_funding_source", order_line_id: bought.neat_id, funding_source_id: other.neat_id, reason: "Gift").error
    assert_equal other, bought.reload.funding_source
    moved = call_as(@world.funding_manager, "set_funding_source", order_line_id: bought.neat_id, funding_source_id: nil, reason: "Back")
    assert_equal [ bought.order_request.neat_id, nil ], [ moved.value["order_request"]["id"], moved.value["line"]["funding_source"] ],
      "they can open this request, so it comes back; null pays the item from the request's source"
    assert_match "not both", call_as(@world.mentor, "set_funding_source", order_request_id: order_request.neat_id, order_line_id: line.neat_id, funding_source_id: nil).error
  end

  test "set_funding_source moves a bought item for a funding manager who can't open its request, as reallocation does" do
    spare = FundingSource.create!(team: @world.club, name: "Spare", kind: :general, active: true, amount_cents: 10_000)
    treasurer = orders_person("Treasurer", teams: [ @world.club ], badges: [ @world.funder_badge ])
    order_request = approved_bought
    line = order_request.order_lines.first
    line.update_columns(funding_source_id: spare.id)

    assert_equal "Not found", call_as(treasurer, "get_order_request", order_request_id: order_request.neat_id).error
    report = call_as(treasurer, "funding_source_report", funding_source_id: spare.neat_id).value
    assert_equal [ line.neat_id ], report["rows"].map { |row| row["order_line_id"] }

    other = FundingSource.create!(team: @world.club, name: "Gift", kind: :general, active: true)
    result = call_as(treasurer, "set_funding_source", order_line_id: line.neat_id, funding_source_id: other.neat_id, reason: "Grant covers it")
    assert_nil result.error
    assert_nil result.value["order_request"], "the request stays out of sight"
    assert_equal [ line.neat_id, other.neat_id ], [ result.value["line"]["id"], result.value["line"]["funding_source"]["id"] ]
    assert_equal other, line.reload.funding_source

    assert_equal "Not found", call_as(@world.outsider, "set_funding_source", order_line_id: line.neat_id, funding_source_id: spare.neat_id,
      reason: "Mine").error, "anyone else can't tell the item exists"
    assert_equal "Not found", call_as(treasurer, "set_funding_source", order_line_id: approved_request(@world).order_lines.first.neat_id,
      funding_source_id: spare.neat_id).error, "an item not yet bought is set from its request, which they can't open"

    sign_in treasurer.user
    post reallocate_orders_request_line_path(order_request, line), params: { funding_source_id: spare.id, reason: "Back" }
    assert_equal spare, line.reload.funding_source, "the reallocation page allows them the same"
  end

  test "record_purchase and record_delivery follow the group's payment methods and delivery problems" do
    order_request = approved_request(@world, lines: [ { description: "Bearing", price: 3, vendor_id: @world.preferred_vendor.id },
      { description: "Belt", price: 9, vendor_id: @world.preferred_vendor.id } ])
    bearing, belt = order_request.order_lines.to_a
    card = PaymentMethod.find_by!(name: "Team card")
    card.retire!
    assert_match "must be one of: Paid personally", call_as(@world.buyer, "record_purchase", lines: [ { id: bearing.neat_id } ], payment_method_id: card.neat_id).error

    gift = PaymentMethod.create!(name: "Gift card")
    result = call_as(@world.buyer, "record_purchase", lines: [ { id: bearing.neat_id } ], payment_method_id: "gift card")
    assert_equal [ gift, nil ], [ Purchase.find_by_neat_id(result.value["purchase"]["id"]).payment_method, Purchase.find_by_neat_id(result.value["purchase"]["id"]).reimburse_to ]
    buy(@world, [ belt ], vendor: @world.preferred_vendor)

    scratched = DeliveryProblemKind.create!(name: "Scratched")
    DeliveryProblemKind.find_by!(key: "wrong_item").retire!
    assert_match "problem_kind_id must be one of: Damaged, Scratched",
      call_as(@world.requester, "record_delivery", order_line_id: belt.neat_id, problem_kind_id: "Wrong item").error
    good = call_as(@world.requester, "record_delivery", order_line_id: bearing.neat_id)
    assert_equal [ "Good", nil ], good.value["delivery"].values_at("condition", "problem_kind")
    flagged = call_as(@world.requester, "record_delivery", order_line_id: belt.neat_id, problem_kind_id: scratched.neat_id)
    assert_equal [ scratched.neat_id, "problem" ], [ flagged.value["delivery"]["problem_kind"]["id"], flagged.value["line"]["status"] ]
  end

  test "get_purchase gives the payment method" do
    order_request = approved_bought([ { description: "Bearing", price: 3 } ])
    purchase = order_request.order_lines.first.purchase
    purchase.update!(payment_method: PaymentMethod.find_by!(name: "Paid personally"), reimburse_to: @world.buyer)
    json = call_as(@world.buyer, "get_purchase", purchase_id: purchase.neat_id).value
    assert_equal [ "Paid personally", true ], json["payment_method"].values_at("name", "reimburse")
    assert_equal @world.buyer.neat_id, json["reimburse_to"]["id"]
  end

  test "list_order_lists gives each picker's active rows to whoever its page shows them to" do
    lists = call_as(@world.buyer, "list_order_lists").value
    assert_equal [ "Team card", "Paid personally" ], lists["payment_methods"].map { |method| method["name"] }
    assert_equal [ false, true ], lists["payment_methods"].map { |method| method["reimburse"] }
    assert_equal [ "Damaged", "Wrong item" ], lists["delivery_problems"].map { |kind| kind["name"] }
    assert_empty lists["approval_steps"], "the Approval Steps screen is for admins"

    assert_empty call_as(@world.requester, "list_order_lists").value["payment_methods"], "the Record purchase form is for buyers"
    assert_equal 2, call_as(@world.requester, "list_order_lists").value["delivery_problems"].size

    steps = call_as(@world.admin, "list_order_lists").value["approval_steps"]
    assert_equal ApprovalStep.active.ordered.map(&:neat_id), steps.map { |step| step["id"] }
    DeliveryProblemKind.find_by!(key: "damaged").retire!
    assert_equal [ "Wrong item" ], call_as(@world.admin, "list_order_lists").value["delivery_problems"].map { |kind| kind["name"] }
  end
end
