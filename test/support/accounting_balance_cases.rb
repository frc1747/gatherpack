# The balance kind's cases, written against what a source records rather
# than any one source's tables, so every source can show it gives the same
# results. A test class includes this module and implements:
#
#   balance_source                         the source (an Accounting::Provider)
#   balance_person(customer)               a person linked to that customer
#   balance_charge(customer, id, total:, due_on: nil)
#                                          a charge, nothing paid yet
#   balance_pay(customer, id, cents, charge:)
#                                          a payment applied to the charge
#   balance_credit(customer, id, cents, charge:)
#                                          a credit (a scholarship, say) applied to it
#   balance_unapplied(customer, id, cents) a payment applied to no charge
#   balance_void(customer, charge)         the charge voided
#   balance_sync                           whatever makes the source's records current
#
# Each case evaluates a balance rule on today = Nov 1, 2026.
module AccountingBalanceCases
  extend ActiveSupport::Concern

  TODAY = Date.new(2026, 11, 1)
  DEPOSIT = { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50, position: 0 }.freeze
  IN_FULL = { name: "Paid in full", due_on: Date.new(2027, 1, 15), balance_at_most_cents: 0, position: 1 }.freeze

  included do
    test "balance: no charges is Not invoiced" do
      person = balance_person("C1")
      assert_equal "not_invoiced", balance_outcome(person).value
    end

    test "balance: paid in full is Paid, even with a milestone passed" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)
      balance_pay("C1", "P1", 40_000, charge: "I1")

      outcome = balance_outcome(person)
      assert_equal [ "paid", 0 ], [ outcome.value, outcome.amount_cents ]
      assert_equal [ 40_000, 40_000 ], outcome.details.values_at(:charged_cents, :paid_cents)
    end

    test "balance: some paid with the deposit met is Partly paid, with the next milestone" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)
      balance_pay("C1", "P1", 25_000, charge: "I1")

      outcome = balance_outcome(person)
      assert_equal [ "partial", 15_000 ], [ outcome.value, outcome.amount_cents ]
      assert_equal({ name: "Paid in full", due_on: IN_FULL[:due_on], catch_up_cents: 15_000 }, outcome.details[:next])
      assert_nil outcome.details[:missed]
    end

    test "balance: nothing paid before any milestone is Not yet paid" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)

      assert_equal "unpaid", balance_outcome(person, today: Date.new(2026, 9, 1)).value
    end

    test "balance: a passed milestone that isn't met is Overdue, with the catch-up" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)
      balance_pay("C1", "P1", 5_000, charge: "I1")

      outcome = balance_outcome(person)
      assert_equal "overdue", outcome.value
      assert_equal({ name: "Deposit", due_on: DEPOSIT[:due_on], catch_up_cents: 15_000 }, outcome.details[:missed])
    end

    test "balance: grace days hold off Overdue" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)

      assert_equal "unpaid", balance_outcome(person, grace_days: 31).value
      assert_equal "overdue", balance_outcome(person, grace_days: 30).value
    end

    test "balance: a credit lowers the balance as a payment does" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)
      balance_pay("C1", "P1", 10_000, charge: "I1")
      balance_credit("C1", "CM1", 30_000, charge: "I1")

      outcome = balance_outcome(person)
      assert_equal [ "paid", 0, 40_000 ], [ outcome.value, outcome.amount_cents, outcome.details[:paid_cents] ]
    end

    test "balance: with no milestones each charge is due in full on its due date" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000, due_on: Date.new(2026, 10, 15))
      balance_pay("C1", "P1", 10_000, charge: "I1")

      outcome = balance_outcome(person, milestones: [])
      assert_equal "overdue", outcome.value
      assert_equal 30_000, outcome.details[:missed][:catch_up_cents]
      assert_equal "partial", balance_outcome(person, milestones: [], today: Date.new(2026, 10, 15)).value
    end

    test "balance: a voided charge doesn't count" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)
      balance_void("C1", "I1")

      assert_equal "not_invoiced", balance_outcome(person).value
    end

    test "balance: unapplied credit is shown, or counted when the rule says so" do
      person = balance_person("C1")
      balance_charge("C1", "I1", total: 40_000)
      balance_unapplied("C1", "P1", 40_000)

      shown = balance_outcome(person)
      assert_equal [ "overdue", 40_000, 40_000 ], [ shown.value, shown.amount_cents, shown.details[:unapplied_credit_cents] ]
      counted = balance_outcome(person, unapplied_credit: "count")
      assert_equal [ "paid", 0 ], [ counted.value, counted.amount_cents ]
    end
  end

  private
    def balance_outcome(person, today: TODAY, milestones: [ DEPOSIT, IN_FULL ], **settings)
      balance_sync
      rule = AccountingRule.create!(name: "Dues #{SecureRandom.hex(3)}", kind: "balance", gateway: balance_source, **settings)
      milestones.each { |milestone| rule.milestones.create!(milestone) }
      Accounting::Evaluation.new(rule, today: today).outcome_for(person)
    end
end
