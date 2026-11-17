require "test_helper"
require "support/orders_world"

# Payment methods and delivery problems on the shared list screen
# (ManagedListsController), registered by orders.
class Orders::OrderListsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "an admin adds a payment method that needs paying back" do
    with_orders(@world) do
      sign_in @world.admin.user
      get managed_list_url(:payment_methods)
      assert_response :success
      assert_select "#managed_list_active li", 2

      post managed_list_rows_url(:payment_methods), params: { row: { name: "Petty cash", reimburse: "1" } }
      assert_redirected_to managed_list_url(:payment_methods)
      assert PaymentMethod.find_by!(name: "Petty cash").reimburse
    end
  end

  test "delivery problems are listed, and the built-in ones can't be deleted" do
    with_orders(@world) do
      sign_in @world.admin.user
      get managed_list_url(:delivery_problem_kinds)
      assert_response :success
      assert_select "#managed_list_active li", 2
      assert_select "#managed_list_active button", text: "Delete", count: 0

      delete managed_list_row_url(:delivery_problem_kinds, DeliveryProblemKind.find_by!(key: "damaged"))
      assert DeliveryProblemKind.exists?(key: "damaged")
    end
  end

  test "the lists are for admins, and gone while orders is off" do
    with_orders(@world) do
      sign_in @world.buyer.user
      get managed_list_url(:payment_methods)
      assert_response :redirect
    end
    with_orders(@world, feature_orders: "false") do
      sign_in @world.admin.user
      get managed_list_url(:payment_methods)
      assert_response :not_found
    end
  end

  test "a retired delivery problem isn't offered when receiving" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10 } ])
      buy(@world, order_request.order_lines.to_a)
      line = order_request.order_lines.first
      DeliveryProblemKind.find_by!(key: "wrong_item").retire!
      sign_in @world.requester.user

      get new_orders_request_line_delivery_url(order_request, line)
      assert_select "select[name='order_delivery[delivery_problem_kind_id]'] option", 2
      assert_select "select[name='order_delivery[delivery_problem_kind_id]'] option", text: /Wrong item/, count: 0

      post orders_request_line_deliveries_url(order_request, line), params: { order_delivery: { quantity: 1, received_on: Date.current.to_s,
        delivery_problem_kind_id: DeliveryProblemKind.find_by!(key: "wrong_item").id } }
      assert_equal 0, line.order_deliveries.count
    end
  end
end
