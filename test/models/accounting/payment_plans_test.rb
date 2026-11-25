require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::PaymentPlansTest < ActiveSupport::TestCase
  include AccountingRulesWorld

  setup do
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @nancy, by: @laura)
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    add_charge("58", "I1", total: 40_000, balance: 30_000)
    add_charge("60", "I2", total: 40_000, balance: 30_000)
    @today = Date.new(2026, 11, 1)
    @rule = create_rule(read_permission: "family", amount_permission: "family", team: @team,
      milestones: [ { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 },
                    { name: "Paid in full", due_on: Date.new(2027, 1, 15), balance_at_most_cents: 0 } ])
  end

  test "a plan replaces the rule's milestones for that person only; removing it restores them" do
    evaluate(@rule, today: @today)
    assert_equal %w[ overdue overdue ], [ result_for(@rule, @nancy).value, result_for(@rule, @janet).value ]

    plan = [ add_plan_row(@nancy, "First payment", Date.new(2026, 10, 1), 30_000),
             add_plan_row(@nancy, "Second payment", Date.new(2026, 12, 1), 15_000),
             add_plan_row(@nancy, "Last payment", Date.new(2027, 3, 1), 0) ]
    evaluate(@rule, today: @today)

    nancy = result_for(@rule, @nancy)
    assert_equal "partial", nancy.value
    assert nancy.on_plan?
    assert_equal [ "First payment", "Second payment", "Last payment" ], nancy.detail(:milestones).map { |milestone| milestone["name"] }
    assert_equal({ "name" => "Second payment", "due_on" => "2026-12-01", "catch_up_cents" => 15_000 }, nancy.detail(:next))
    janet = result_for(@rule, @janet)
    assert_equal "overdue", janet.value
    assert_not janet.on_plan?
    assert_equal "Deposit", janet.detail(:missed)["name"]

    plan.each(&:destroy!)
    evaluate(@rule, today: @today)
    assert_equal "overdue", result_for(@rule, @nancy).value
    assert_not result_for(@rule, @nancy).on_plan?
  end

  test "plan rows give an amount or a percent, like the rule's milestones, and only on balance rules" do
    row = @rule.person_milestones.build(person: @nancy, name: "First payment", due_on: Date.new(2026, 12, 1))
    assert_not row.valid?
    row.balance_at_most = "150"
    assert row.valid?
    assert_equal 15_000, row.balance_at_most_cents

    count = create_rule("Receipts", kind: "count")
    assert_not count.person_milestones.build(person: @nancy, name: "First", due_on: Date.new(2026, 12, 1), balance_at_most_cents: 0).valid?
  end

  test "the person, their guardian and admins see the plan; a leader and a grant holder see the status only" do
    robert = create_rule_person("Robert", "King")
    treasurer = create_rule_badge("Treasurer")
    BadgeAssignment.create!(badge: treasurer, person: robert)
    @rule.badge_grants.create!(badge: treasurer, amounts: true)
    add_plan_row(@nancy, "First payment", Date.new(2026, 12, 1), 0)
    evaluate(@rule, today: @today)
    result = result_for(@rule, @nancy)

    with_settings(feature_badges: "true") do
      rule = @rule.reload
      seers = { subject: @nancy, guardian: @margaret, admin: @laura, leader: @andrew, grant_holder: robert }
        .select { |_, viewer| Accounting::RuleAccess.new(viewer, @nancy, rule).sees_plan? }.keys
      assert_equal %i[ subject guardian admin ], seers
      assert Accounting::RuleAccess.new(robert, @nancy, rule).can_see_amounts?
      assert Accounting::RuleAccess.new(@andrew, @nancy, rule).plan_hidden?(result)
      assert_not Accounting::RuleAccess.new(@margaret, @nancy, rule).plan_hidden?(result)
    end
  end

  test "Duplicate doesn't copy plans" do
    add_plan_row(@nancy, "First payment", Date.new(2026, 12, 1), 0)

    copy = @rule.duplicate!

    assert_equal 1, @rule.person_milestones.count
    assert_equal 0, copy.person_milestones.count
    assert_not copy.on_plan?(@nancy)
  end

  test "the hook catalog offers payment plans, and a plan's hooks see it with its note" do
    assert_includes Hook.catalog, "accounting_person_milestones - create"
    assert_includes Hook.catalog, "accounting_person_milestones - update"
    assert_includes Hook.catalog, "accounting_person_milestones - destroy"
    assert_not_includes Hook.catalog, "accounting_reminders - create"

    Hook.create!(name: "Plan set up", event: "accounting_person_milestones - create", code: "Thread.current[:accounting_plan_hook] = model")
    Hook.create!(name: "Plan changed", event: "accounting_person_milestones - update", code: "Thread.current[:accounting_plan_update] = model.note")
    row = add_plan_row(@nancy, "First payment", Date.new(2026, 12, 1), 0, note: "Agreed with the family by phone")
    assert_equal row, Thread.current[:accounting_plan_hook]
    assert_equal "Agreed with the family by phone", Thread.current[:accounting_plan_hook].note

    row.update!(note: "Moved a week")
    assert_equal "Moved a week", Thread.current[:accounting_plan_update]
  ensure
    Thread.current[:accounting_plan_hook] = nil
    Thread.current[:accounting_plan_update] = nil
  end

  private
    def add_plan_row(person, name, due_on, at_most_cents, note: nil)
      @rule.person_milestones.create!(person: person, name: name, due_on: due_on, balance_at_most_cents: at_most_cents, note: note, created_by: @laura)
    end
end
