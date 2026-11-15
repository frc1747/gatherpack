require "test_helper"
require "support/orders_world"

class Orders::LineReceiptsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup do
    @world = build_orders_world
  end

  def ordered_line(quantity: 2)
    order_request = approved_request(@world, lines: [ { description: "Gear", quantity: quantity, price: 10 } ])
    buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
    [ order_request.reload, order_request.order_lines.first ]
  end

  def problem_line
    order_request, line = ordered_line
    line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged, note: "Cracked")
    [ order_request.reload, line.reload ]
  end

  test "a buyer marks an item received with a note and no delivery record" do
    with_orders(@world) do
      order_request, line = ordered_line
      sign_in @world.buyer.user

      post mark_received_orders_request_line_url(order_request, line), params: { note: "Went to the lab" }
      assert_redirected_to orders_request_url(order_request)
      assert line.reload.received?
      assert_empty line.order_deliveries
      assert_equal "Went to the lab", order_request.events.last.comment
    end
  end

  test "a note is needed to mark an item received without a delivery" do
    with_orders(@world) do
      order_request, line = ordered_line
      sign_in @world.buyer.user

      post mark_received_orders_request_line_url(order_request, line), params: { note: "" }
      assert_response :redirect
      assert line.reload.ordered?
    end
  end

  test "the requester can't mark an item received without a delivery" do
    with_orders(@world) do
      order_request, line = ordered_line
      sign_in @world.requester.user

      post mark_received_orders_request_line_url(order_request, line), params: { note: "Got it" }
      assert_redirected_to root_url
      assert line.reload.ordered?
    end
  end

  test "the buyer reorders a problem like for like with no new approval" do
    with_orders(@world) do
      order_request, line = problem_line
      sign_in @world.buyer.user

      assert_difference -> { order_request.order_lines.count }, 1 do
        post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder" }
      end
      assert_redirected_to orders_request_url(order_request)
      replacement = order_request.order_lines.reload.order(:position).last
      assert replacement.approved?
      assert_equal 1, replacement.quantity, "only the damaged piece is replaced"
      assert_equal line.description, replacement.description
      assert_equal 2, line.reload.quantity, "what was bought stays as it was"
      assert_equal 1, line.to_come_quantity, "the piece still on its way can be received"
      assert line.ordered?
      assert_not order_request.reload.received?
    end
  end

  test "the buyer reorders everything when all of it came damaged" do
    with_orders(@world) do
      order_request, line = ordered_line
      line.record_delivery!(by: @world.requester, quantity: 2, condition: :damaged, note: "Crushed")
      sign_in @world.buyer.user

      post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder" }
      assert line.reload.cancelled?, "nothing good arrived and nothing more is coming"
      assert_equal 2, order_request.order_lines.reload.order(:position).last.quantity
    end
  end

  test "cancelling a problem cancels only what didn't arrive good and keeps the rest receivable" do
    with_orders(@world) do
      order_request, line = problem_line
      sign_in @world.buyer.user

      assert_no_difference -> { order_request.order_lines.count } do
        post resolve_orders_request_line_url(order_request, line), params: { resolution: "cancel", comment: "Not needed now" }
      end
      assert_equal "Not needed now", order_request.events.last.comment
      assert line.reload.ordered?
      assert_equal 2, line.quantity
      assert line.open_to_receive?

      line.record_delivery!(by: @world.requester, quantity: 1, condition: :good)
      assert line.reload.received?
    end
  end

  test "cancelling a problem when nothing more is coming cancels the item" do
    with_orders(@world) do
      order_request, line = ordered_line
      line.record_delivery!(by: @world.requester, quantity: 2, condition: :damaged)
      sign_in @world.buyer.user

      post resolve_orders_request_line_url(order_request, line), params: { resolution: "cancel", comment: "Gave up" }
      assert line.reload.cancelled?
    end
  end

  test "a second damaged delivery after a settled one counts only itself" do
    with_orders(@world) do
      order_request, line = ordered_line(quantity: 4)
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      line.resolve_problem!(:cancel, by: @world.buyer, comment: "Skip it")
      assert_equal 4, line.reload.quantity

      line.record_delivery!(by: @world.requester, quantity: 1, condition: :wrong_item)
      assert line.reload.problem?
      assert_equal 1, line.problem_quantity
      assert_equal 2, line.to_come_quantity
    end
  end

  test "a replacement for part of the damaged pieces leaves the item's quantity and the rest to arrive" do
    with_orders(@world) do
      order_request, line = ordered_line(quantity: 3)
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged, note: "Cracked")
      sign_in @world.buyer.user

      post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder", quantity: 1 }
      assert_redirected_to orders_request_url(order_request)
      assert_equal 3, line.reload.quantity
      assert line.ordered?
      assert_equal 1, order_request.order_lines.reload.order(:position).last.quantity

      line.record_delivery!(by: @world.requester, quantity: 2, condition: :good)
      assert line.reload.received?, "2 good and 1 settled account for all 3"
    end
  end

  test "settling a problem leaves the purchase total and what was spent alone" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request = approved_request(@world, funding_source: source, lines: [ { description: "Gear", quantity: 3, price: 10 } ])
      purchase = buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor)
      line = order_request.order_lines.first
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      total = purchase.reload.total_cents
      spent = source.reload.spent_cents
      assert_equal 3000, total

      line.reload.resolve_problem!(:cancel, by: @world.buyer, comment: "Not worth it")
      assert_equal total, purchase.reload.total_cents
      assert_equal spent, source.reload.spent_cents
      assert_equal 3, line.reload.quantity

      line.record_delivery!(by: @world.requester, quantity: 2, condition: :good)
      assert line.reload.received?
      assert_equal total, purchase.reload.total_cents
    end
  end

  test "a replacement above the damaged count is refused" do
    with_orders(@world) do
      order_request, line = problem_line
      sign_in @world.buyer.user

      assert_no_difference -> { order_request.order_lines.count } do
        post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder", quantity: 2 }
        post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder", quantity: 0 }
      end
      assert line.reload.problem?
    end
  end

  test "settling a problem where some came good and nothing more is coming leaves the item received, replacing only the damaged" do
    with_orders(@world) do
      order_request, line = ordered_line(quantity: 3)
      line.record_delivery!(by: @world.requester, quantity: 2, condition: :good)
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :wrong_item, note: "Wrong size")
      sign_in @world.buyer.user

      post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder" }
      assert line.reload.received?
      assert_equal 3, line.quantity
      assert_equal 1, order_request.order_lines.reload.order(:position).last.quantity
    end
  end

  test "cancelling a problem needs a reason" do
    with_orders(@world) do
      order_request, line = problem_line
      sign_in @world.buyer.user

      post resolve_orders_request_line_url(order_request, line), params: { resolution: "cancel", comment: "" }
      assert line.reload.problem?
    end
  end

  test "only a buyer resolves a problem" do
    with_orders(@world) do
      order_request, line = problem_line
      sign_in @world.requester.user

      post resolve_orders_request_line_url(order_request, line), params: { resolution: "reorder" }
      assert_redirected_to root_url
      assert line.reload.problem?
    end
  end
end
