require "test_helper"
require "support/orders_world"

class Orders::ConfigTest < ActiveSupport::TestCase
  include OrdersWorld

  test "with no steps, one step for everyone stands in" do
    steps = Orders::Config.approval_steps

    assert_equal [ "approval" ], steps.map(&:key)
    assert_equal 0, steps.first.minimum_cents
    assert_equal "Approval", Orders::Config.step("approval").name
  end

  test "steps are the active rows in position order, with minimums in cents" do
    badge = Badge.create!(name: "Treasurer badge", short: "TB", color: "#000000", badge_type: BadgeType.first || BadgeType.create!(name: "Role"),
      permission: :added_by_admin)
    ApprovalStep.create!(key: "old", name: "Old step", minimum_cents: 0, position: 1, active: false)
    ApprovalStep.create!(key: "mentor", name: "Mentor", minimum_cents: 0, position: 3)
    treasurer = ApprovalStep.create!(key: "treasurer", name: "Treasurer", minimum: "500.50", position: 4)
    treasurer.approvers.create!(badge: badge)

    assert_equal %w[mentor treasurer], Orders::Config.approval_steps.map(&:key)
    assert_equal [ 0, 50050 ], Orders::Config.approval_steps.map(&:minimum_cents)
    assert_equal [ [ badge, nil ] ], Orders::Config.step("treasurer").reach.grants
    assert_equal "Old step", Orders::Config.step("old").name
  end

  test "price tolerance takes the larger of the percentage and the amount" do
    with_settings(orders_price_tolerance: "10%, 25") do
      tolerance = Orders::Config.price_tolerance

      assert_equal 2500, tolerance.allowance_cents(10_000)   # 10% of $100 is $10; $25 is larger
      assert_equal 10_000, tolerance.allowance_cents(100_000) # 10% of $1000 is $100
    end
    with_settings(orders_price_tolerance: "5%") do
      assert_equal 500, Orders::Config.price_tolerance.allowance_cents(10_000)
    end
  end

  test "approval steps and paid with are no longer settings" do
    assert_nil Settings.get(:orders_approval_steps)
    assert_nil Settings.get(:orders_paid_with)
  end
end
