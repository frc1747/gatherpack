require "test_helper"
require "support/orders_world"

class Orders::ToBuyTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "holds the same items Orders::WaitingOn counts" do
    with_orders(@world) do
      approved_request(@world, lines: [ { description: "A", price: 1 }, { description: "B", price: 1, vendor_id: @world.preferred_vendor.id } ])
      approved_request(@world, by: @world.outsider, team: @world.art)

      to_buy = Orders::ToBuy.new(@world.buyer)
      assert_equal Orders::WaitingOn.new(@world.buyer).lines_to_buy, to_buy.groups.sum { |group| group.lines.size }
      assert_equal 2, to_buy.lines.size
    end
  end

  test "Other store names group together whatever their case" do
    with_orders(@world) do
      approved_request(@world, lines: [ { description: "A", price: 1, other_vendor_name: "Corner Store" } ])
      approved_request(@world, lines: [ { description: "B", price: 1, other_vendor_name: "corner store" } ])

      groups = Orders::ToBuy.new(@world.buyer).groups
      assert_equal 1, groups.size
      assert_equal :other, groups.first.key
      assert_equal 2, groups.first.lines.size
    end
  end

  test "within a group, items needed soonest come first and no date comes last" do
    with_orders(@world) do
      approved_request(@world, needed_by: nil, lines: [ { description: "Whenever", price: 1 } ])
      approved_request(@world, needed_by: Date.current + 9, lines: [ { description: "Later", price: 1 } ])
      approved_request(@world, needed_by: Date.current + 1, lines: [ { description: "Soon", price: 1 } ])

      lines = Orders::ToBuy.new(@world.buyer).groups.first.lines
      assert_equal %w[Soon Later Whenever], lines.map(&:description)
    end
  end

  test "a selection must be items still waiting for this buyer" do
    with_orders(@world) do
      art = approved_request(@world, by: @world.outsider, team: @world.art)
      to_buy = Orders::ToBuy.new(@world.buyer)

      assert_raises(Orders::Refused) { to_buy.selection([]) }
      error = assert_raises(Orders::Refused) { to_buy.selection([ art.order_lines.first.id ]) }
      assert_match "no longer waiting", error.message
    end
  end
end
