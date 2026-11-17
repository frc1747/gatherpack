require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  setup do
    # Robotics
    # └── Robotics Jr
    # Drama (unrelated)
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @robotics_jr = Team.create!(name: "Robotics Jr", team_type: team_types(:one), parent: @robotics)
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))
    @creator = User.create!(email: "admin@example.com", password: "Password1!", admin: true)

    @travel = LedgerTag.create!(name: "Travel")
    @food = LedgerTag.create!(name: "Food")
    period = BudgetPeriod.create!(name: "Robotics 2026", team: @robotics, starts_at: 1.month.ago, ends_at: 1.month.from_now)
    @budget_id = Budget.create!(budget_period: period, amount: 100, ledger_tags: [ @travel ]).id
  end

  test "counts tagged entries from the team's own ledgers" do
    fund = entry(Ledger.create!(name: "Robotics fund", team: @robotics), -10, @travel)
    reserve = entry(Ledger.create!(name: "Robotics reserve", team: @robotics), -5, @travel)

    budget = Budget.find(@budget_id)
    assert_equal [ fund, reserve ].sort_by(&:id), budget.ledger_entries.sort_by(&:id)
    assert_equal(-1_500, budget.actual_amount_cents)
    assert_equal 8_500, budget.remaining_amount_cents
  end

  test "ignores entries with the same tags in another team's ledger, a sub-team's included" do
    entry(Ledger.create!(name: "Drama fund", team: @drama), -42, @travel)
    entry(Ledger.create!(name: "Robotics Jr fund", team: @robotics_jr), -5, @travel)

    budget = Budget.find(@budget_id)
    assert_empty budget.ledger_entries
    assert_equal 0, budget.actual_amount_cents
    assert_equal 10_000, budget.remaining_amount_cents
  end

  test "still needs every tag of the budget and an entry within the period" do
    ledger = Ledger.create!(name: "Robotics fund", team: @robotics)
    Budget.find(@budget_id).update!(ledger_tags: [ @travel, @food ])
    entry(ledger, -1, @travel)
    entry(ledger, -2, @travel, @food).update_column(:created_at, 2.months.ago)
    both = entry(ledger, -3, @travel, @food)

    assert_equal [ both ], Budget.find(@budget_id).ledger_entries.to_a
  end

  private

  # Budget.find each time: a budget memoizes its entries, and saving one
  # computes them (money-rails validates actual_amount) before its tags exist.

  def entry(ledger, amount, *tags)
    LedgerEntry.create!(ledger: ledger, amount: amount, remark: "Entry", created_by: @creator, ledger_tags: tags)
  end
end
