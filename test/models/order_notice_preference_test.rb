require "test_helper"
require "support/orders_world"

class OrderNoticePreferenceTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a person with no saved choice gets the daily digest" do
    preference = OrderNoticePreference.for(@world.buyer)

    assert_predicate preference, :buyer_digest?
    assert_predicate preference, :new_record?
  end

  test "a saved choice is found, one for each person" do
    saved = OrderNoticePreference.create!(person: @world.buyer, buyer_notices: :off)

    assert_equal saved, OrderNoticePreference.for(@world.buyer)
    assert_raises(ActiveRecord::RecordNotUnique) { OrderNoticePreference.create!(person: @world.buyer) }
  end
end
