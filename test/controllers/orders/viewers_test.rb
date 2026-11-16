require "test_helper"
require "support/orders_world"

# orders_viewers: members of the listed teams (and the teams below) see
# every request that isn't a draft, without deciding, buying or receiving.
class Orders::ViewersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a viewer opens a request on an unrelated team but can't decide it" do
    with_orders(@world, orders_viewers: @world.robotics.name) do
      order_request = submitted_request(@world, by: @world.outsider, team: @world.art, title: "Paint brushes")
      sign_in @world.builder.user

      get orders_request_url(order_request)
      assert_response :success
      assert_match "Paint brushes", response.body
      assert_select ".orders-decision-bar", 0

      post orders_request_decisions_url(order_request), params: { decision: "approved", comment: "Fine" }
      assert order_request.reload.submitted?
      assert_empty order_request.order_approvals
    end
  end

  test "a viewer can't buy or receive a request they only see" do
    with_orders(@world, orders_viewers: @world.robotics.name) do
      order_request = approved_request(@world, by: @world.outsider, team: @world.art, title: "Paint brushes")
      sign_in @world.builder.user

      get to_buy_orders_purchases_url
      assert_no_match "Paint brushes", response.body
      get orders_deliveries_url
      assert_no_match "Paint brushes", response.body
    end
  end

  test "a viewer doesn't see a draft" do
    with_orders(@world, orders_viewers: @world.robotics.name) do
      draft = draft_request(@world, by: @world.outsider, team: @world.art)
      sign_in @world.builder.user

      get orders_request_url(draft)
      assert_response :not_found
    end
  end
end
