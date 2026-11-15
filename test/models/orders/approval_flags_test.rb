require "test_helper"
require "support/orders_world"

class Orders::ApprovalFlagsTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def keys(order_request, today: Date.current)
    Orders::ApprovalFlags.new(order_request.reload, today: today).map(&:key)
  end

  test "a complete request from a preferred store with a funding source has no flags" do
    with_orders(@world) do
      budget = FundingSource.create!(team: @world.robotics, name: "Budget")
      order_request = submitted_request(@world, purpose: "Drive train", funding_source: budget,
        lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id, vendor_part_number: "G-1" } ])

      assert_empty keys(order_request)
    end
  end

  test "each gap an approver should check is flagged" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [
        { description: "Not sure" },
        { description: "Other", other_vendor_name: "Corner Shop", url: "https://corner.example/x", price: 1 },
        { description: "Listed", vendor_id: @world.other_vendor.id, manufacturer_part_number: "M-1", price: 1 }
      ])

      assert_equal %i[no_purpose no_funding not_sure no_link no_price other_store not_preferred], keys(order_request)
    end
  end

  test "a needed-by date in the past or within three days is flagged; a later one isn't" do
    with_orders(@world) do
      today = Date.new(2026, 3, 10)
      order_request = submitted_request(@world, purpose: "Kit")

      order_request.update_columns(needed_by: today - 1)
      assert_includes keys(order_request, today: today), :past
      order_request.update_columns(needed_by: today + 3)
      assert_includes keys(order_request, today: today), :soon
      order_request.update_columns(needed_by: today + 4)
      assert_not_includes keys(order_request, today: today), :soon
    end
  end

  test "an item with its own funding source isn't flagged for the request having none" do
    with_orders(@world) do
      grant = FundingSource.create!(team: @world.robotics, name: "Grant")
      order_request = submitted_request(@world, lines: [ { description: "Gear", funding_source_id: grant.id } ])

      assert_not_includes keys(order_request), :no_funding
    end
  end
end
