require "test_helper"
require "support/orders_world"

class Orders::MenuAndPrefetchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a member's Orders menu has no To buy or Reports" do
    skip "needs NavItem visible checks" unless Orders::SettingsEditor.in_menu?

    with_orders(@world) do
      sign_in @world.requester.user
      get orders_requests_url
      assert_select ".nav-item a[href='#{orders_requests_path}']"
      assert_select "a[href='#{to_buy_orders_purchases_path}']", 0
      assert_select "a[href='#{orders_reports_path}']", 0

      sign_in @world.buyer.user
      get orders_requests_url
      assert_select ".nav-item a[href='#{to_buy_orders_purchases_path}']"
    end
  end

  test "the Buying notices page is retired: no route, and no link from To buy or the dashboard" do
    with_orders(@world) do
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/orders/notice_preference/edit") }
      assert_not Rails.application.routes.url_helpers.respond_to?(:edit_orders_notice_preference_path)

      sign_in @world.buyer.user
      get to_buy_orders_purchases_url
      assert_response :success
      assert_select "a", text: "Buying notices", count: 0
      get root_url
      assert_select "a", text: "Buying notices", count: 0
    end
  end

  test "a prefetch of a forbidden page leaves no flash behind" do
    with_orders(@world) do
      sign_in @world.requester.user

      get to_buy_orders_purchases_url, headers: { "X-Sec-Purpose" => "prefetch" }
      assert_response :forbidden
      assert_nil flash[:notice]

      get orders_requests_url
      assert_no_match "not allowed", response.body
    end
  end

  test "a real visit to a forbidden page still shows the flash" do
    with_orders(@world) do
      sign_in @world.requester.user
      get to_buy_orders_purchases_url
      assert_redirected_to root_url
      assert_equal "You are not allowed to do that", flash[:notice]
    end
  end
end
