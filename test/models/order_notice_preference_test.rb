require "test_helper"
require "support/orders_world"

class OrderNoticePreferenceTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "a holder of a buyer grant with no saved choice gets the daily digest" do
    with_orders(@world) do
      preference = OrderNoticePreference.for(@world.buyer)

      assert_predicate preference, :buyer_digest?
      assert_predicate preference, :new_record?
    end
  end

  test "an admin or manager without a buyer grant gets nothing until they choose" do
    with_orders(@world) do
      assert_predicate OrderNoticePreference.for(@world.admin), :buyer_off?
      assert_predicate OrderNoticePreference.for(@world.manager), :buyer_off?
    end
  end

  test "a person's choice is deleted with them" do
    OrderNoticePreference.create!(person: @world.buyer, buyer_notices: :off)

    assert_difference -> { OrderNoticePreference.count }, -1 do
      @world.buyer.destroy!
    end
  end

  test "a saved choice is found, one for each person" do
    saved = OrderNoticePreference.create!(person: @world.buyer, buyer_notices: :off)

    assert_equal saved, OrderNoticePreference.for(@world.buyer)
    assert_raises(ActiveRecord::RecordNotUnique) { OrderNoticePreference.create!(person: @world.buyer) }
  end
end
