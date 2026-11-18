require "test_helper"
require "support/orders_world"

class Orders::RequestsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "orders routes refuse while the feature is off" do
    order_request = with_orders(@world) { submitted_request(@world) }
    sign_in @world.requester.user

    with_settings(orders_settings(@world, feature_orders: "false")) do
      get orders_request_url(order_request)
      assert_redirected_to root_url
    end
  end

  test "the request page shows to someone who can see it, with no slot filled yet" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.teammate.user

      get orders_request_url(order_request)
      assert_response :success
      assert_select "h1", order_request.display_title
      assert_match "Waiting for approval", response.body
    end
  end

  test "the request page is refused to someone who can't see it" do
    with_orders(@world) do
      order_request = submitted_request(@world)
      sign_in @world.builder.user

      get orders_request_url(order_request)
      assert_response :not_found
    end
  end

  test "the list shows what the viewer can see, and mine=1 only their own and followed" do
    with_orders(@world) do
      submitted_request(@world, title: "Mine")
      submitted_request(@world, title: "Teammate's", by: @world.teammate)
      sign_in @world.requester.user

      get orders_requests_url
      assert_response :success
      assert_match "Teammate&#39;s", response.body

      get orders_requests_url(mine: 1)
      assert_match "Mine", response.body
      assert_no_match "Teammate&#39;s", response.body
    end
  end

  test "the new request page is for people in orders_requesters" do
    with_orders(@world, orders_requesters: @world.robotics.name) do
      sign_in @world.requester.user
      get new_orders_request_url
      assert_response :success

      sign_in @world.outsider.user
      get new_orders_request_url
      assert_response :redirect
    end
  end

  test "the dashboard shows the My Orders card with the viewer's to-dos" do
    with_orders(@world) do
      submitted_request(@world, title: "Spare battery")
      sign_in @world.mentor.user

      get root_url
      assert_response :success
      assert_select "h2", "My Orders"
      assert_match "Spare battery", response.body
      assert_match "Review", response.body
    end
  end

  test "the dashboard has no My Orders card while the feature is off" do
    with_settings(orders_settings(@world, feature_orders: "false")) do
      sign_in @world.mentor.user

      get root_url
      assert_response :success
      assert_select "h2", text: "My Orders", count: 0
    end
  end
end
