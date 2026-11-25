require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::RuleEvaluationTest < ActiveSupport::TestCase
  include AccountingRulesWorld
  include ActiveJob::TestHelper

  setup do
    @team = create_rule_team("Robotics")
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @andrew = create_rule_person("Andrew", "Fuller", team: @team)
    @janet = create_rule_person("Janet", "Leverling", customer: "60")
    add_charge("58", "I1", total: 40_000, balance: 10_000)
  end

  test "everyone linked to a customer gets a result, and the team's members even with no records" do
    rule = create_rule(team: @team)

    evaluate(rule)

    assert_equal({ @nancy => "partial", @andrew => "not_invoiced", @janet => "not_invoiced" },
      rule.results.includes(:person).to_h { |result| [ result.person, result.value ] })
    assert_equal 10_000, result_for(rule, @nancy).amount_cents
    assert_equal "partial", @nancy.accounting_result(rule.key).value
  end

  test "evaluation saves only changes and fires result changed when the value or amount moves" do
    rule = create_rule
    seen = capture_changes { evaluate(rule) }
    assert_equal [ [ @nancy, nil, "partial", nil, 10_000 ], [ @janet, nil, "not_invoiced", nil, 0 ] ].sort_by { |row| row.first.first_name },
      seen.map { |change| [ change.person, change.old_value, change.new_value, change.old_amount_cents, change.new_amount_cents ] }.sort_by { |row| row.first.first_name }
    assert seen.all? { |change| change.rule == rule && change.on_plan == false }

    changed_at = result_for(rule, @nancy).changed_at
    travel 1.hour do
      assert_empty capture_changes { evaluate(rule) }
      assert_equal changed_at, result_for(rule, @nancy).reload.changed_at
      assert result_for(rule, @nancy).evaluated_at > changed_at
    end

    accounting_source.accounting_records.find_by!(external_id: "I1").update!(balance_cents: 0)
    paid = capture_changes { evaluate(rule) }.sole
    assert_equal [ @nancy, "partial", "paid", 10_000, 0 ], [ paid.person, paid.old_value, paid.new_value, paid.old_amount_cents, paid.new_amount_cents ]
  end

  test "a person who no longer qualifies loses their result" do
    rule = create_rule
    evaluate(rule)
    link = accounting_source.accounting_customer_links.find_by!(person: @janet)

    Accounting::CustomerLinks.new(accounting_source).unlink!(link)
    gone = capture_changes { evaluate(rule) }.sole

    assert_equal [ @janet, "not_invoiced", nil ], [ gone.person, gone.old_value, gone.new_value ]
    assert_nil result_for(rule, @janet)
  end

  test "only the given people are evaluated" do
    rule = create_rule
    Accounting::Evaluation.new(rule).run([ @janet.id ])

    assert_equal [ @janet ], rule.results.map(&:person)
  end

  test "the rule's record hooks fire" do
    Hook.create!(name: "Rule changed", event: "accounting_rules - update", code: "Thread.current[:accounting_rule_hook] = model")
    rule = create_rule

    rule.update!(description: "Due by January")

    assert_equal rule, Thread.current[:accounting_rule_hook]
  ensure
    Thread.current[:accounting_rule_hook] = nil
  end

  test "the hook catalog offers rules and result changes" do
    assert_includes Hook.catalog, "accounting_rules - create"
    assert_includes Hook.catalog, "accounting_rules - result changed"
    assert_not_includes Hook.catalog, "accounting_rule_results - update"
    assert_not_includes Hook.catalog, "accounting_rule_milestones - update"
  end

  test "the evaluate job runs only while the feature is on" do
    rule = create_rule

    with_accounting(false) { Accounting::EvaluateRuleJob.perform_now(rule) }
    assert_empty rule.results
    with_accounting { Accounting::EvaluateRuleJob.perform_now(rule) }
    assert_equal 2, rule.results.count
  end

  test "the nightly job evaluates every enabled rule, and nothing while the feature is off" do
    on = create_rule
    create_rule("Old dues", enabled: false)

    with_accounting(false) { assert_no_enqueued_jobs(only: Accounting::EvaluateRuleJob) { Accounting::NightlyJob.perform_now } }
    with_accounting do
      assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ on ]) { Accounting::NightlyJob.perform_now }
      assert_enqueued_jobs 1, only: Accounting::EvaluateRuleJob
    end
  end

  test "linking a customer queues the source's rules for that person" do
    rule = create_rule
    steven = create_rule_person("Steven", "Buchanan")

    assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ rule, [ steven.id ] ]) { link_customer(steven, "70") }
  end

  test "a sync queues the source's rules for the people whose records changed" do
    rule = create_rule
    sync = Accounting::Sync.new(accounting_source)
    accounting_source.define_singleton_method(:normalize) do |_type, raw|
      { role: "charge", customer_external_id: raw["customer"], total_cents: 100, balance_cents: 100 }
    end

    assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ rule, [ @janet.id ] ]) do
      sync.upsert("Invoice", { "Id" => "900", "customer" => "60" })
      sync.send(:finish, accounting_source.accounting_records.where(external_id: "900").to_a)
    end
    assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ rule, nil ]) { sync.send(:finish, [], everyone: true) }
  end

  test "Duplicate moves the season on and copies no results" do
    badge = create_rule_badge("Treasurer")
    rule = create_rule("2026-27 Dues", read_permission: "family", amount_permission: "self", unapplied_credit: "count",
      filters: { "items" => [ "dues" ], "txn_date_from" => "2026-07-01", "txn_date_to" => "2027-06-30" },
      milestones: [ { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 } ])
    rule.badge_grants.create!(badge: badge, amounts: true)
    evaluate(rule)

    copy = rule.duplicate!

    assert_equal [ "2027-28 Dues", false ], [ copy.name, copy.enabled ]
    assert_not_equal rule.key, copy.key
    assert_equal({ "items" => [ "dues" ], "txn_date_from" => "2027-07-01", "txn_date_to" => "2028-06-30" }, copy.filters)
    assert_equal [ [ "Deposit", Date.new(2027, 10, 1), 50 ] ], copy.milestones.map { |m| [ m.name, m.due_on, m.balance_at_most_percent ] }
    assert_equal [ "family", "self", "count" ], [ copy.read_permission, copy.amount_permission, copy.unapplied_credit ]
    assert_equal [ [ badge, true ] ], copy.badge_grants.map { |grant| [ grant.badge, grant.amounts ] }
    assert_empty copy.results
    assert_equal "Fees (copy)", AccountingRule.next_season_name("Fees")
    assert_equal "Given in 2027", AccountingRule.next_season_name("Given in 2026")
  end

  private
    def capture_changes
      seen = []
      Hook.where(event: Accounting::Evaluation::EVENT).delete_all
      Hook.create!(name: "Capture", event: Accounting::Evaluation::EVENT, code: "Thread.current[:accounting_changes] << model")
      Thread.current[:accounting_changes] = seen
      yield
      seen
    ensure
      Thread.current[:accounting_changes] = nil
    end
end
