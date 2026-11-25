require "test_helper"
require_relative "../support/accounting_rules_world"

# Treasurer totals on Account Status and the rule page: counts over the
# people the viewer sees, money only over those whose amounts they may see,
# and no totals when that's nobody.
class AccountingTotalsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    @andrew = create_rule_person("Andrew", "Fuller", team: @team)
    @robert = create_rule_person("Robert", "King")
    add_charge("58", "I1", total: 40_000, balance: 10_000)
    add_charge("60", "I2", total: 40_000, balance: 0)
    @rule = create_rule(read_permission: "team", amount_permission: "self", team: @team)
    evaluate(@rule)
  end

  test "counts cover everyone the viewer sees; money only the people whose amounts they may see" do
    sign_in @nancy.user

    with_accounting { get accounting_rules_path }
    assert_select "##{dom_id(@rule)} .accounting-counts", text: "Not invoiced 1 · Paid 1 · Partly paid 1"
    assert_select "##{dom_id(@rule)} .accounting-totals", text: /Charged \$400\.00 · Paid \$300\.00 ·\s+Balance remaining \$100\.00\s+\(of 1 person\)/

    with_accounting { get accounting_rule_path(@rule) }
    assert_select ".accounting-counts", text: "Not invoiced 1 · Paid 1 · Partly paid 1"
    assert_select ".accounting-totals", text: /Balance remaining \$100\.00\s+\(of 1 person\)/
  end

  test "totals are hidden when the viewer may see nobody's amounts" do
    mentor = create_rule_badge("Mentor")
    BadgeAssignment.create!(badge: mentor, person: @robert)
    @rule.badge_grants.create!(badge: mentor, amounts: false)
    sign_in @robert.user

    with_settings(feature_badges: "true") do
      with_accounting { get accounting_rule_path(@rule) }
    end

    assert_select ".accounting-counts", text: "Not invoiced 1 · Paid 1 · Partly paid 1"
    assert_select ".accounting-totals", count: 0
    assert_no_match "Charged", response.body
  end

  test "a treasurer's grant with amounts sums everyone the grant covers, without an \"of\" when that's everyone" do
    treasurer = create_rule_badge("Treasurer")
    BadgeAssignment.create!(badge: treasurer, person: @robert)
    @rule.badge_grants.create!(badge: treasurer, amounts: true)
    sign_in @robert.user

    with_settings(feature_badges: "true") do
      with_accounting { get accounting_rule_path(@rule) }
    end

    assert_select ".accounting-totals", text: /Charged \$800\.00 · Paid \$700\.00 ·\s+Balance remaining \$100\.00/
    assert_no_match "(of ", response.body
  end
end
