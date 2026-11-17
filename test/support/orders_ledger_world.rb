# A ledger for the orders world's robotics team, and Budgets with their own
# ledger tag, for the ledger and budget parts of orders (spec §6).
#
#   ledger = orders_ledger(world)
#   budget = orders_budget(world, "Build", amount_cents: 100_000)
#   source = FundingSource.create!(team: world.robotics, name: "Build", budget: budget)
module OrdersLedgerWorld
  def orders_ledger(world, name: "Robotics account")
    Ledger.create!(team: world.robotics, name: name)
  end

  def orders_budget(world, tag_name, amount_cents: 100_000)
    period = BudgetPeriod.create!(team: world.robotics, name: "This season", starts_at: 1.month.ago, ends_at: 1.month.from_now)
    budget = Budget.create!(budget_period: period, amount_cents: amount_cents)
    BudgetTagging.create!(budget: budget, ledger_tag: LedgerTag.create!(name: "#{tag_name} #{SecureRandom.hex(3)}"))
    budget.reload
  end
end
