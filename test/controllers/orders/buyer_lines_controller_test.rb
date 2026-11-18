require "test_helper"
require "support/orders_world"

class Orders::BuyerLinesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a buyer marks an ordered item delayed with an expected date" do
    with_orders(@world) do
      order_request = approved_request(@world)
      line = order_request.order_lines.first
      buy(@world, [ line ])
      sign_in @world.buyer.user

      post backorder_orders_request_line_url(order_request, line), params: { expected_on: "2030-02-01" }

      assert_redirected_to orders_request_url(order_request)
      assert_equal "Gear is marked delayed.", flash[:notice]
      assert line.reload.backordered?
      assert_equal Date.new(2030, 2, 1), line.expected_on
    end
  end

  test "a bad date is refused" do
    with_orders(@world) do
      order_request = approved_request(@world)
      line = order_request.order_lines.first
      buy(@world, [ line ])
      sign_in @world.buyer.user

      post backorder_orders_request_line_url(order_request, line), params: { expected_on: "soon" }

      assert_equal "That isn't a date.", flash[:alert]
      assert line.reload.ordered?
    end
  end

  test "lowering a quantity needs no approval; raising it past the tolerance does" do
    with_orders(@world, orders_price_tolerance: "10%, 25") do
      order_request = approved_request(@world, lines: [ { description: "Wheel", price: 50 } ], needed_by: nil)
      order_request.order_lines.first.update!(quantity: 2)
      order_request.update!(approved_total_cents: 10_000)
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      post change_quantity_orders_request_line_url(order_request, line), params: { quantity: 1 }
      assert_equal "Wheel: quantity changed to 1.", flash[:notice]
      assert line.reload.approved?

      post change_quantity_orders_request_line_url(order_request, line), params: { quantity: 4 }
      assert_match "needs re-approval", flash[:notice]
      assert line.reload.needs_reapproval?
    end
  end

  test "a quantity of zero is refused with the reason" do
    with_orders(@world) do
      order_request = approved_request(@world)
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      post change_quantity_orders_request_line_url(order_request, line), params: { quantity: 0 }

      assert_match "Quantity must be greater than 0", flash[:alert]
      assert_equal 1, line.reload.quantity
    end
  end

  test "a buyer splits an item: part now, the rest waits" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Bolt", price: 1, quantity: 10 } ])
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      post split_orders_request_line_url(order_request, line), params: { quantity_now: 4 }

      assert_equal "Bolt is split: 4 now, 6 later.", flash[:notice]
      assert_equal [ 4, 6 ], order_request.order_lines.reload.map(&:quantity).sort
      assert order_request.order_lines.all?(&:approved?)
    end
  end

  test "cancelling needs a reason" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 1 }, { description: "B", price: 1 } ])
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      post cancel_orders_request_line_url(order_request, line), params: { reason: "" }
      assert_equal "Give a reason for cancelling.", flash[:alert]
      assert line.reload.approved?

      post cancel_orders_request_line_url(order_request, line), params: { reason: "Discontinued" }
      assert_equal "A is cancelled.", flash[:notice]
      assert line.reload.cancelled?
      assert_equal "Discontinued", order_request.events.where(action: "cancelled").last.comment
    end
  end

  test "only buyers for the request's team may change its items" do
    with_orders(@world) do
      order_request = approved_request(@world)
      line = order_request.order_lines.first
      sign_in @world.requester.user

      post cancel_orders_request_line_url(order_request, line), params: { reason: "Nope" }

      assert_equal "You are not allowed to do that", flash[:notice]
      assert line.reload.approved?
    end
  end

  test "an empty quantity or split is refused with a message, not an error page" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Bolt", price: 1, quantity: 10 } ])
      line = order_request.order_lines.first
      sign_in @world.buyer.user

      post change_quantity_orders_request_line_url(order_request, line), params: { quantity: "" }
      assert_redirected_to orders_request_url(order_request)
      assert_match "Quantity must be greater than 0", flash[:alert]

      post split_orders_request_line_url(order_request, line), params: { quantity_now: "" }
      assert_redirected_to orders_request_url(order_request)
      assert_equal "Split off fewer than 10.", flash[:alert]
      assert_equal 10, line.reload.quantity
    end
  end
end
