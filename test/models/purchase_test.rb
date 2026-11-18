require "test_helper"
require "support/orders_world"

class PurchaseTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "one purchase can combine lines from two requests" do
    with_orders(@world) do
      first = approved_request(@world, lines: [ { description: "A", price: 10, vendor_id: @world.preferred_vendor.id } ])
      second = approved_request(@world, lines: [ { description: "B", price: 20, vendor_id: @world.preferred_vendor.id } ], by: @world.teammate)

      purchase = buy(@world, first.order_lines + second.order_lines, vendor: @world.preferred_vendor, shipping_cents: 600, tax_cents: 300)

      assert_equal [ first, second ].map(&:id).sort, purchase.order_requests.map(&:id).sort
      assert_equal 3000 + 900, purchase.total_cents
      assert first.reload.ordering?
      assert second.reload.ordering?
    end
  end

  test "shipping and tax are shared out by line cost and add up exactly" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 10 }, { description: "B", price: 20 }, { description: "C", price: 20 } ])
      purchase = buy(@world, order_request.order_lines.to_a, shipping_cents: 700, tax_cents: 300)

      shares = purchase.reload.extras_shares
      assert_equal 1000, shares.values.sum
      a, b, c = order_request.order_lines.map { |line| shares[line.id] }
      assert_equal 200, a
      assert_equal [ 400, 400 ], [ b, c ]
    end
  end

  test "a line already on a purchase can't join another, even from a stale copy" do
    with_orders(@world) do
      order_request = approved_request(@world)
      stale = order_request.order_lines.first
      buy(@world, [ order_request.order_lines.first ])

      error = assert_raises(Orders::Refused) { buy(@world, [ stale ]) }
      assert_match "already on an order", error.message
      assert_equal 1, Purchase.count
    end
  end

  test "a buyer can't buy for a team outside their reach" do
    with_orders(@world) do
      art = approved_request(@world, by: @world.outsider, team: @world.art)

      error = assert_raises(Orders::Refused) { buy(@world, art.order_lines.to_a) }
      assert_match "don't buy for", error.message
      assert art.order_lines.first.reload.approved?
      assert_equal 0, Purchase.count
    end
  end

  test "a line bought at its estimate isn't sent for re-approval because another line was" do
    with_orders(@world, orders_price_tolerance: "10%, 25") do
      order_request = approved_request(@world, lines: [ { description: "A", price: 100 }, { description: "B", price: 100 } ])
      a, b = order_request.order_lines.to_a
      buy(@world, [ a ], prices: { a.id => 20_000 })
      buy(@world, [ b ], prices: { b.id => 10_000 })

      assert a.reload.needs_reapproval?
      assert b.reload.ordered?
      assert_equal 1, order_request.events.where(action: "reapproval_needed").count
    end
  end

  test "a line cancelled after purchase still counts in the purchase's total and share of extras" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 100 } ])
      purchase = buy(@world, order_request.order_lines.to_a, shipping_cents: 1000)
      line = order_request.order_lines.first.reload
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      line.reload.resolve_problem!(:reorder, by: @world.buyer)

      assert line.reload.cancelled?
      assert_equal 11_000, purchase.reload.total_cents
      assert_equal({ line.id => 1000 }, purchase.extras_shares)
    end
  end

  test "a line from another vendor is refused" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "A", price: 1, vendor_id: @world.other_vendor.id } ])

      assert_raises(Orders::Refused) { buy(@world, order_request.order_lines.to_a, vendor: @world.preferred_vendor) }
    end
  end

  test "a not-sure line takes the purchase's vendor" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Something like this" } ])
      buy(@world, order_request.order_lines.to_a, vendor: @world.other_vendor, prices: { order_request.order_lines.first.id => 899 })

      line = order_request.order_lines.first.reload
      assert_equal @world.other_vendor, line.vendor
      assert_equal 899, line.actual_unit_price_cents
      assert line.ordered?
      changes = order_request.events.last.field_changes
      assert_equal [ nil, @world.other_vendor.id ], changes["vendor_id"]
    end
  end

  test "an actual price within the tolerance is recorded and nothing waits" do
    with_orders(@world, orders_price_tolerance: "10%, 25") do
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      buy(@world, order_request.order_lines.to_a, prices: { order_request.order_lines.first.id => 12_000 })

      assert order_request.order_lines.first.reload.ordered?
      assert order_request.reload.ordering?
    end
  end

  test "an actual price past the tolerance sends the line back to the final step" do
    with_settings(two_step_settings(@world, minimum: 500).merge(orders_price_tolerance: "10%, 25")) do
      Orders::Current.reset
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      buy(@world, order_request.order_lines.to_a, prices: { order_request.order_lines.first.id => 13_000 })
      order_request.reload
      line = order_request.order_lines.first

      assert line.needs_reapproval?
      assert order_request.ordering?
      assert order_request.needs_reapproval?
      assert_equal "reapproval_needed", order_request.events.last.action
      assert_equal "mentor", order_request.decision_step.key, "the final needed step for a $130 request"

      order_request.decide!(:approved, by: @world.mentor)
      assert line.reload.ordered?
      assert_equal 13_000, order_request.reload.approved_total_cents
    end
  end

  test "declining a re-approval cancels the changed lines" do
    with_orders(@world) do
      order_request = approved_request(@world, lines: [ { description: "Kit", price: 100 } ])
      order_request.order_lines.first.change_quantity!(5, by: @world.buyer)
      order_request.reload.decide!(:declined, by: @world.mentor, comment: "Too many")

      assert order_request.order_lines.first.reload.cancelled?
      assert order_request.reload.cancelled?
    end
  end

  test "a purchase needs a vendor or a store name" do
    purchase = Purchase.new(buyer: people(:one))

    assert_not purchase.valid?
    assert purchase.errors[:vendor].any?
  end
end
