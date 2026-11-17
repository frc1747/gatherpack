require "test_helper"
require "support/orders_world"

class OrderNoticeMarkTest < ActiveSupport::TestCase
  include OrdersWorld

  setup do
    @world = build_orders_world
    @request = draft_request(@world)
  end

  test "a reminder is claimed once for each occasion" do
    assert OrderNoticeMark.claim(@request, "needed_soon", "2026-11-20")
    assert_not OrderNoticeMark.claim(@request, "needed_soon", "2026-11-20")
    assert OrderNoticeMark.claim(@request, "needed_soon", "2026-11-18")
    assert OrderNoticeMark.claim(@request, "undecided", "2026-11-20")
    assert_equal 2, OrderNoticeMark.where(order_request: @request).count
  end
end
