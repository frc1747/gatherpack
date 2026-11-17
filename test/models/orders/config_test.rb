require "test_helper"
require "support/settings_test_helper"

class Orders::ConfigTest < ActiveSupport::TestCase
  include SettingsTestHelper

  test "the default is one step for everyone" do
    with_settings(orders_approval_steps: "") do
      steps = Orders::Config.approval_steps

      assert_equal [ "approval" ], steps.map(&:key)
      assert_equal 0, steps.first.minimum_cents
    end
  end

  test "steps parse with minimums in cents, and bad JSON falls back to the default" do
    json = JSON.generate([ { "key" => "mentor", "name" => "Mentor", "minimum" => 0 },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => 500.5, "approvers" => [ "Badge > Team" ] } ])
    with_settings(orders_approval_steps: json) do
      assert_equal [ 0, 50050 ], Orders::Config.approval_steps.map(&:minimum_cents)
      assert_equal [ "Badge > Team" ], Orders::Config.step("treasurer").approvers
    end
    with_settings(orders_approval_steps: "{not json") do
      assert_equal [ "approval" ], Orders::Config.approval_steps.map(&:key)
    end
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

  test "paid with choices say which need reimbursing" do
    with_settings(orders_paid_with: "") do
      choices = Orders::Config.paid_with

      assert_equal [ false, true ], choices.map(&:reimburse)
    end
  end
end
