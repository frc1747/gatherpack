require "test_helper"
require "support/orders_world"

class Orders::PurchaseSplitTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "shares shipping and tax across a purchase's requests by their lines' cost" do
    with_orders(@world) do
      first = approved_request(@world, lines: [ { description: "A", price: 30 } ])
      second = approved_request(@world, lines: [ { description: "B", price: 10 } ], by: @world.teammate)
      purchase = buy(@world, first.order_lines + second.order_lines, shipping_cents: 300, tax_cents: 100)

      totals = Orders::PurchaseSplit.new(purchase.reload).by_request
      assert_equal 3000, totals[first.id].cost_cents
      assert_equal 300, totals[first.id].extras_cents
      assert_equal 100, totals[second.id].extras_cents
      assert_equal purchase.total_cents, totals.values.sum(&:total_cents)
    end
  end

  test "rows group by team and month for reports" do
    with_orders(@world) do
      robotics = approved_request(@world, lines: [ { description: "A", price: 10 } ])
      build = approved_request(@world, by: @world.builder, team: @world.build, lines: [ { description: "B", price: 10 } ])
      buy(@world, robotics.order_lines + build.order_lines, shipping_cents: 201, ordered_on: Date.new(2026, 3, 9))

      rows = Orders::PurchaseSplit.rows(Purchase.includes(:vendor, order_lines: :order_request))
      by_team = Orders::PurchaseSplit.totals(rows, by: :team_id)
      assert_equal 201, by_team.values.sum(&:extras_cents)
      assert_equal [ 1000, 1000 ], by_team.values.map(&:cost_cents)
      assert_equal [ Date.new(2026, 3, 1) ], Orders::PurchaseSplit.totals(rows, by: :month).keys
    end
  end
end
