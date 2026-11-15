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
      assert_equal 1, line.reload.quantity, "the piece still on its way stays on the item"
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
      assert_equal 1, line.quantity
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
      assert_equal 3, line.reload.quantity

      line.record_delivery!(by: @world.requester, quantity: 1, condition: :wrong_item)
      assert line.reload.problem?
      assert_equal 1, line.problem_quantity
      assert_equal 2, line.to_come_quantity
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
