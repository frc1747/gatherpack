require "test_helper"
require "support/orders_world"

class FundingSourceTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "spent counts purchases at actual prices plus their share of shipping and tax; committed counts approved lines not bought" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget", amount_cents: 100_000, spent_outside_cents: 5_000)
      order_request = approved_request(@world, lines: [ { description: "A", price: 10, quantity: 2 }, { description: "B", price: 30 } ], funding_source: source)
      first, second = order_request.order_lines.to_a
      buy(@world, [ first ], prices: { first.id => 1100 }, shipping_cents: 500, tax_cents: 100)

      source.reload
      assert_equal 2200 + 600, source.spent_cents
      assert_equal 3000, source.committed_cents
      assert_equal 100_000 - 2800 - 3000 - 5000, source.remaining_cents
      assert second.reload.approved?
    end
  end

  test "spent keeps a bought line that is later cancelled: it was paid for" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request = approved_request(@world, funding_source: source, lines: [ { description: "A", price: 100 } ])
      buy(@world, order_request.order_lines.to_a, shipping_cents: 1000)
      assert_equal 11_000, source.reload.spent_cents

      line = order_request.order_lines.first.reload
      line.record_delivery!(by: @world.requester, quantity: 1, condition: :damaged)
      replacement = line.reload.resolve_problem!(:reorder, by: @world.buyer)
      assert_equal 11_000, source.reload.spent_cents
      assert_equal 10_000, source.committed_cents, "the replacement waits for a buyer"

      buy(@world, [ replacement ])
      assert_equal 21_000, source.reload.spent_cents
    end
  end

  test "a purchase with lines on two sources shares its extras between them" do
    with_orders(@world) do
      general = FundingSource.create!(team: @world.robotics, name: "General")
      grant = FundingSource.create!(team: @world.robotics, name: "Grant", kind: :restricted, restriction: "Tools")
      order_request = submitted_request(@world, funding_source: general,
        lines: [ { description: "Drill", price: 30, funding_source_id: grant.id }, { description: "Bits", price: 10 } ])
      order_request.decide!(:approved, by: @world.mentor, fits_restriction: true)
      buy(@world, order_request.reload.order_lines.to_a, shipping_cents: 400)

      assert_equal 3000 + 300, grant.reload.spent_cents
      assert_equal 1000 + 100, general.reload.spent_cents
    end
  end

  test "a line's own source overrides the request's" do
    with_orders(@world) do
      general = FundingSource.create!(team: @world.robotics, name: "General")
      grant = FundingSource.create!(team: @world.robotics, name: "Grant")
      order_request = draft_request(@world, funding_source: general,
        lines: [ { description: "A", price: 1, funding_source_id: grant.id }, { description: "B", price: 1 } ])
      a, b = order_request.order_lines.to_a

      assert_equal grant.id, a.effective_funding_source_id
      assert_equal general.id, b.effective_funding_source_id
      assert_equal [ a.id ], grant.order_lines.pluck(:id)
    end
  end

  test "a source without an amount has no remaining; over the amount is flagged, not blocked" do
    with_orders(@world) do
      open_ended = FundingSource.create!(team: @world.robotics, name: "Open")
      assert_nil open_ended.remaining_cents

      small = FundingSource.create!(team: @world.robotics, name: "Small", amount_cents: 500)
      order_request = submitted_request(@world, funding_source: small, lines: [ { description: "Kit", price: 10 } ])
      assert_equal(-500, small.numbers.remaining_after_cents(order_request))
      assert small.numbers.over_after?(order_request)

      order_request.decide!(:approved, by: @world.mentor)
      assert order_request.reload.approved?
    end
  end

  test "a funding manager can move a bought line to another source, with a reason" do
    with_orders(@world) do
      general = FundingSource.create!(team: @world.robotics, name: "General")
      grant = FundingSource.create!(team: @world.robotics, name: "Grant")
      order_request = approved_request(@world, funding_source: general)
      line = order_request.order_lines.first
      assert_raises(Orders::Refused) { line.reallocate_funding!(grant, by: @world.funding_manager, reason: "x") }

      buy(@world, [ line ])
      assert_raises(Orders::Refused) { line.reload.reallocate_funding!(grant, by: @world.funding_manager, reason: "") }
      line.reload.reallocate_funding!(grant, by: @world.funding_manager, reason: "Grant covers tools")

      assert_equal 1000, grant.reload.spent_cents
      assert_equal 0, general.reload.spent_cents
      assert_equal [ "General", "Grant" ], order_request.events.last.field_changes["funding_source"]
    end
  end

  test "a restricted source needs its restriction, and dates in order" do
    assert_not FundingSource.new(team: @world.robotics, name: "Gift", kind: :restricted).valid?
    assert_not FundingSource.new(team: @world.robotics, name: "Dates", starts_on: Date.new(2027, 2, 1), ends_on: Date.new(2027, 1, 1)).valid?
  end

  test "usable by its team and the teams below" do
    source = FundingSource.new(team: @world.robotics, name: "Robotics")

    assert source.usable_by?(@world.robotics)
    assert source.usable_by?(@world.build)
    assert_not source.usable_by?(@world.club)
    assert_not source.usable_by?(@world.art)
  end
end
