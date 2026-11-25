require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::RuleFiltersTest < ActiveSupport::TestCase
  include AccountingRulesWorld

  setup do
    @nancy = create_rule_person("Nancy", "Davolio", customer: "58")
  end

  test "items, classes and locations match when any id overlaps" do
    add_charge("58", "I1", total: 100, items: %w[ dues shirt ], class_ids: [ "robotics" ], location_ids: [ "east" ])
    add_charge("58", "I2", total: 200, items: [ "travel" ], class_ids: [ "outreach" ], location_ids: [ "west" ])

    assert_equal [ "I1" ], matching(items: %w[ dues camp ])
    assert_equal [ "I2" ], matching(classes: [ "outreach" ])
    assert_equal [ "I1" ], matching(locations: [ "east" ])
    assert_equal [], matching(items: [ "dues" ], classes: [ "outreach" ])
    assert_equal %w[ I1 I2 ], matching({})
  end

  test "date bounds are inclusive" do
    add_charge("58", "I1", total: 100, txn_date: Date.new(2026, 8, 31), due_on: Date.new(2026, 10, 1))
    add_charge("58", "I2", total: 100, txn_date: Date.new(2026, 9, 1), due_on: Date.new(2026, 10, 15))
    add_charge("58", "I3", total: 100, txn_date: Date.new(2027, 6, 30), due_on: Date.new(2026, 11, 1))
    add_charge("58", "I4", total: 100, txn_date: Date.new(2027, 7, 1), due_on: Date.new(2026, 11, 2))

    assert_equal %w[ I2 I3 ], matching(txn_date_from: "2026-09-01", txn_date_to: "2027-06-30")
    assert_equal %w[ I2 I3 ], matching(due_date_from: "2026-10-15", due_date_to: "2026-11-01")
  end

  test "min_total skips records whose total is below it" do
    add_charge("58", "I1", total: 4_999)
    add_charge("58", "I2", total: 5_000)

    assert_equal [ "I2" ], matching(min_total: 5_000)
  end

  test "filters decide which charges a balance rule counts" do
    add_charge("58", "I1", total: 40_000, balance: 0, items: [ "dues" ])
    add_charge("58", "I2", total: 30_000, balance: 30_000, items: [ "travel" ])

    assert_equal "paid", outcome_for(create_rule("Dues", filters: { items: [ "dues" ] }), @nancy).value
    assert_equal "unpaid", outcome_for(create_rule("Travel fee", filters: { items: [ "travel" ] }), @nancy).value
  end

  test "the form's filters are stored as ids and ISO dates, without blanks" do
    rule = create_rule(filters: { "items" => [ "", "dues" ], "classes" => [ "" ], "txn_date_from" => "2026-09-01", "txn_date_to" => "", "min_total" => "500", "junk" => "x" })

    assert_equal({ "items" => [ "dues" ], "txn_date_from" => "2026-09-01", "min_total" => 500 }, rule.filters)
    assert_not AccountingRule.new(name: "Bad", kind: "balance", gateway: accounting_source, filters: { "txn_date_from" => "soon" }).valid?
  end

  test "393#10: a date that doesn't exist and a negative minimum are refused" do
    rule = AccountingRule.new(name: "Bad", kind: "balance", gateway: accounting_source, filters: { "txn_date_from" => "2026-02-31" })
    assert_not rule.valid?
    assert_includes rule.errors[:filters], "have a date that isn't a date"

    rule = AccountingRule.new(name: "Bad", kind: "balance", gateway: accounting_source, filters: { "min_total" => -5_000 })
    assert_not rule.valid?
    assert_includes rule.errors[:filters], "can't skip records under less than nothing"
  end

  private
    def matching(filters)
      scope = accounting_source.accounting_records.where(role: "charge")
      Accounting::RecordFilter.new(filters.stringify_keys).apply(scope).order(:external_id).pluck(:external_id)
    end
end
