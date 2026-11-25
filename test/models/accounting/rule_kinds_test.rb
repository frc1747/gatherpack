require "test_helper"
require_relative "../../support/accounting_rules_world"
require_relative "../../support/accounting_balance_cases"

class Accounting::RuleKindsTest < ActiveSupport::TestCase
  include AccountingRulesWorld
  include AccountingBalanceCases

  setup do
    @nancy = create_rule_person("Nancy", "Davolio", customer: "58")
  end

  # The balance cases on QuickBooks' records, as its normalize leaves them:
  # each payment and credit lowers its charge's balance.
  def balance_source = accounting_source
  def balance_person(customer) = create_rule_person("Andrew", "Fuller", customer: customer)
  def balance_charge(customer, id, total:, due_on: nil) = add_charge(customer, id, total: total, due_on: due_on)
  def balance_pay(customer, id, cents, charge:) = apply(customer, id, cents, charge, "payment")
  def balance_credit(customer, id, cents, charge:) = apply(customer, id, cents, charge, "credit")
  def balance_unapplied(customer, id, cents) = add_payment(customer, id, total: cents, unapplied: cents)
  def balance_void(customer, charge) = accounting_source.accounting_records.find_by!(external_id: charge).update!(voided: true, balance_cents: 0)
  def balance_sync = nil

  test "milestones by amount and by percent of what was charged" do
    add_charge("58", "I1", total: 40_000, balance: 25_000)
    rule = create_rule(milestones: [ { name: "Half", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 },
                                     { name: "Most", due_on: Date.new(2026, 10, 2), balance_at_most_cents: 10_000 } ])

    outcome = outcome_for(rule, @nancy, today: Date.new(2026, 11, 1))

    assert_equal "overdue", outcome.value
    assert_equal [ [ "Half", 20_000, false, 5_000 ], [ "Most", 10_000, false, 15_000 ] ],
      outcome.details[:milestones].map { |check| check.values_at(:name, :limit_cents, :met, :catch_up_cents) }
    assert_equal "Half", outcome.details[:missed][:name]
  end

  test "the next milestone is the first one not met and not yet due" do
    add_charge("58", "I1", total: 40_000, balance: 15_000)
    rule = create_rule(milestones: [ { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 },
                                     { name: "Paid in full", due_on: Date.new(2027, 3, 1), balance_at_most_cents: 0 } ])

    details = outcome_for(rule, @nancy, today: Date.new(2026, 11, 1)).details

    assert_equal [ true, false ], details[:milestones].map { |check| check[:met] }
    assert_equal({ name: "Paid in full", due_on: Date.new(2027, 3, 1), catch_up_cents: 15_000 }, details[:next])
  end

  test "with no milestones and no due dates from the source, nobody is ever overdue" do
    add_charge("58", "I1", total: 40_000)
    rule = create_rule
    rule.gateway.define_singleton_method(:capabilities) { Set.new }

    assert rule.never_overdue?
    assert_equal "unpaid", outcome_for(rule, @nancy, today: Date.new(2030, 1, 1)).value
    rule.milestones.create!(name: "Paid in full", due_on: Date.new(2027, 1, 1), balance_at_most_cents: 0)
    assert_not rule.reload.never_overdue?
  end

  test "393#5: counted unapplied credit covers the earliest charges' due dates first" do
    add_charge("58", "I1", total: 20_000, due_on: Date.new(2026, 10, 1))
    add_charge("58", "I2", total: 20_000, due_on: Date.new(2027, 1, 15))
    add_payment("58", "P1", total: 20_000, unapplied: 20_000)
    rule = create_rule(unapplied_credit: "count")

    outcome = outcome_for(rule, @nancy, today: Date.new(2026, 11, 1))

    assert_equal [ "partial", 20_000 ], [ outcome.value, outcome.amount_cents ]
    assert_equal [ [ Date.new(2026, 10, 1), true, 0 ], [ Date.new(2027, 1, 15), false, 20_000 ] ],
      outcome.details[:milestones].map { |check| check.values_at(:due_on, :met, :catch_up_cents) }
  end

  test "393#5: counted unapplied credit lowers a past charge's catch-up" do
    add_charge("58", "I1", total: 40_000, due_on: Date.new(2026, 10, 1))
    add_payment("58", "P1", total: 20_000, unapplied: 20_000)
    rule = create_rule(unapplied_credit: "count")

    outcome = outcome_for(rule, @nancy, today: Date.new(2026, 11, 1))

    assert_equal [ "overdue", 20_000 ], [ outcome.value, outcome.amount_cents ]
    assert_equal 20_000, outcome.details[:missed][:catch_up_cents]
  end

  test "the balance details name each charge by its public label with its pay link" do
    add_charge("58", "I1", total: 40_000, balance: 10_000, label: "Invoice 1042 · Dues", pay_url: "https://pay.example.com/1042",
      description: "Scholarship agreed")
    rule = create_rule

    charge = outcome_for(rule, @nancy).details[:charges].sole

    assert_equal [ "Invoice 1042 · Dues", 40_000, 10_000, "https://pay.example.com/1042" ], charge.values_at(:label, :total_cents, :balance_cents, :pay_url)
    assert_not_includes charge.values, "Scholarship agreed"
  end

  test "amount sums what was invoiced, or only matching lines with items" do
    add_charge("58", "I1", total: 40_000, items: [ "dues" ])
    add_record("58", "charge", "I2", total_cents: 30_000, balance_cents: 0, item_ids: %w[ dues travel ],
      lines: [ { "item_id" => "dues", "amount_cents" => 10_000 }, { "item_id" => "travel", "amount_cents" => 20_000 } ])
    add_record("58", "receipt", "R1", total_cents: 5_000, item_ids: [ "shirt" ], lines: [ { "item_id" => "shirt", "amount_cents" => 5_000 } ])

    all = outcome_for(create_rule("All invoiced", kind: "amount", measure: "invoiced"), @nancy)
    dues = outcome_for(create_rule("Dues invoiced", kind: "amount", measure: "invoiced", filters: { "items" => [ "dues" ] }), @nancy)

    assert_equal [ "some", 75_000 ], [ all.value, all.amount_cents ]
    assert_equal 50_000, dues.amount_cents
  end

  test "amount sums what was paid less refunds, or what was applied to matching charges with items" do
    add_charge("58", "I1", total: 40_000, balance: 10_000, items: [ "dues" ])
    add_charge("58", "I2", total: 20_000, balance: 0, items: [ "travel" ])
    add_payment("58", "P1", total: 50_000, applied: { "I1" => 30_000, "I2" => 20_000 })
    add_record("58", "receipt", "R1", total_cents: 5_000, item_ids: [ "dues" ], lines: [ { "item_id" => "dues", "amount_cents" => 5_000 } ])
    add_record("58", "refund", "F1", total_cents: 2_000, item_ids: [ "travel" ], lines: [ { "item_id" => "travel", "amount_cents" => 2_000 } ])

    paid = outcome_for(create_rule("Paid", kind: "amount", measure: "paid"), @nancy)
    dues = outcome_for(create_rule("Dues paid", kind: "amount", measure: "paid", filters: { "items" => [ "dues" ] }), @nancy)

    assert_equal 53_000, paid.amount_cents
    assert_equal 35_000, dues.amount_cents
  end

  test "393#6b: paid with categories or locations counts what was applied to the charges they match" do
    add_charge("58", "I1", total: 40_000, balance: 10_000, items: [ "dues" ], class_ids: [ "robotics" ], location_ids: [ "east" ])
    add_charge("58", "I2", total: 20_000, balance: 0, items: [ "dues" ], class_ids: [ "drama" ], location_ids: [ "west" ])
    add_payment("58", "P1", total: 50_000, applied: { "I1" => 30_000, "I2" => 20_000 })

    robotics = outcome_for(create_rule("Robotics paid", kind: "amount", measure: "paid", filters: { "classes" => [ "robotics" ] }), @nancy)
    east_dues = outcome_for(create_rule("East dues paid", kind: "amount", measure: "paid", filters: { "items" => [ "dues" ], "locations" => [ "east" ] }), @nancy)

    assert_equal [ "some", 30_000 ], [ robotics.value, robotics.amount_cents ]
    assert_equal 30_000, east_dues.amount_cents
  end

  test "amount with nothing is None" do
    assert_equal [ "none", 0 ], outcome_for(create_rule("Given", kind: "amount", measure: "paid"), @nancy).to_h.values_at(:value, :amount_cents)
  end

  test "count counts matching records, narrowed by roles" do
    add_record("58", "receipt", "R1", total_cents: 5_000)
    add_record("58", "receipt", "R2", total_cents: 7_000)
    add_payment("58", "P1", total: 1_000)

    all = outcome_for(create_rule("Records", kind: "count"), @nancy)
    receipts = outcome_for(create_rule("Receipts", kind: "count", filters: { "roles" => [ "receipt" ] }), @nancy)

    assert_equal [ "some", 3 ], [ all.value, all.details[:count] ]
    assert_equal 2, receipts.details[:count]
  end

  test "custom code returns a hash, a value, or an error for admins" do
    add_record("58", "receipt", "R1", total_cents: 5_000, data: { "Memo" => "gift" })

    hash = create_rule("Custom hash", kind: "custom", code: 'total = records.sum(:total_cents); { value: "given", amount_cents: total, details: { memo: records.first.data["Memo"], people: customers.count } }')
    string = create_rule("Custom string", kind: "custom", code: 'person.first_name == "Nancy" ? "yes" : "no"')
    broken = create_rule("Custom broken", kind: "custom", code: 'raise "no books"')

    assert_equal [ "given", 5_000, { "memo" => "gift", "people" => 1 } ], outcome_for(hash, @nancy).to_h.values_at(:value, :amount_cents, :details)
    assert_equal "yes", outcome_for(string, @nancy).value
    error = outcome_for(broken, @nancy)
    assert_equal [ "error", "RuntimeError: no books" ], [ error.value, error.details[:error] ]
  end

  test "labels are renamable per rule" do
    rule = create_rule(labels: { "partial" => "Deposit paid", "paid" => "" })

    assert_equal "Deposit paid", rule.label_for("partial")
    assert_equal "Paid", rule.label_for("paid")
    assert_equal "Overdue", rule.label_for("overdue")
  end

  test "a rule needing a role its source doesn't copy isn't evaluated" do
    rule = create_rule("Given", kind: "amount", measure: "paid")
    accounting_source.update!(synced_entities: "Customer Invoice")

    assert_equal [ "payment" ], rule.reload.missing_roles
    assert_empty evaluate(rule)
    assert_empty rule.results
  end

  test "393#7: roles a rule's filter names, and charges a paid amount with items reads, must be copied too" do
    accounting_source.update!(synced_entities: "Customer Invoice Payment CreditMemo Item")
    receipts = create_rule("Receipts", kind: "count", filters: { "roles" => [ "receipt" ] })
    receipt_total = create_rule("Receipt total", kind: "amount", measure: "invoiced", filters: { "roles" => [ "receipt" ] })
    add_record("58", "receipt", "R1", total_cents: 5_000)

    assert_equal [ "receipt" ], receipts.missing_roles
    assert_equal [ "receipt" ], receipt_total.missing_roles
    assert_empty evaluate(receipts)
    assert_empty receipts.results
    assert_empty create_rule("Everything", kind: "count").missing_roles

    accounting_source.update!(synced_entities: "Customer Payment")
    dues_paid = create_rule("Dues paid", kind: "amount", measure: "paid", filters: { "items" => [ "dues" ] })
    assert_equal [ "charge" ], dues_paid.missing_roles
  end

  private
    # A payment or credit applied to a charge, which lowers the charge's
    # balance as the source would.
    def apply(customer, id, cents, charge_id, role)
      charge = accounting_source.accounting_records.find_by!(external_id: charge_id)
      charge.update!(balance_cents: charge.balance_cents - cents)
      add_payment(customer, id, total: cents, applied: { charge_id => cents }, role: role)
    end
end
