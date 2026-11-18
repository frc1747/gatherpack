require "test_helper"
require "support/orders_world"

class Orders::NoticePreferencesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a buyer sees their choice, defaulting to the digest, and changes it" do
    with_orders(@world) do
      sign_in @world.buyer.user
      get edit_orders_notice_preference_url
      assert_response :success
      assert_select "input[type=radio][value=digest][checked]"

      patch orders_notice_preference_url, params: { order_notice_preference: { buyer_notices: "immediate" } }
      assert_redirected_to edit_orders_notice_preference_url
      assert_predicate OrderNoticePreference.find_by(person: @world.buyer), :buyer_immediate?

      get edit_orders_notice_preference_url
      assert_select "input[type=radio][value=immediate][checked]"
    end
  end

  test "a manager who doesn't hold a buyer grant gets the digest too, and can opt out" do
    with_orders(@world) do
      sign_in @world.manager.user
      get edit_orders_notice_preference_url
      assert_select "input[type=radio][value=digest][checked]"

      patch orders_notice_preference_url, params: { order_notice_preference: { buyer_notices: "off" } }
      assert_predicate OrderNoticePreference.find_by(person: @world.manager), :buyer_off?
    end
  end

  test "a choice that isn't one of the options is refused" do
    with_orders(@world) do
      sign_in @world.buyer.user
      patch orders_notice_preference_url, params: { order_notice_preference: { buyer_notices: "bogus" } }

      assert_redirected_to edit_orders_notice_preference_url
      assert_nil OrderNoticePreference.find_by(person: @world.buyer)
    end
  end

  test "someone with nothing to buy has no choice to make" do
    with_orders(@world) do
      sign_in @world.requester.user
      get edit_orders_notice_preference_url
      assert_includes [ 302, 403, 404 ], response.status
      patch orders_notice_preference_url, params: { order_notice_preference: { buyer_notices: "off" } }
      assert_nil OrderNoticePreference.find_by(person: @world.requester)
    end
  end

  test "the page is off while Orders is off" do
    sign_in @world.buyer.user
    get edit_orders_notice_preference_url
    assert_redirected_to root_url
  end
end
