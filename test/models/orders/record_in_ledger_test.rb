require "test_helper"
require "support/orders_world"
require "support/orders_ledger_world"

# Record in ledger (spec §6): one finalized expense entry for the purchase,
# split per funding source, tagged for linked Budgets.
class Orders::RecordInLedgerTest < ActiveSupport::TestCase
  include OrdersWorld
  include OrdersLedgerWorld

  setup do
    @world = build_orders_world
    @ledger = orders_ledger(@world)
  end

  test "records a finalized expense entry for the purchase total, with receipts, metadata and the budget's tags" do
    with_orders(@world) do
      budget = orders_budget(@world, "Build")
      source = FundingSource.create!(team: @world.robotics, name: "Build", budget: budget)
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 10, quantity: 2 } ])
      order_request.update!(funding_source: source)
      purchase = buy(@world, order_request.order_lines, vendor_order_number: "A-1", shipping_cents: 500, tax_cents: 100)
      purchase.receipts.attach(io: StringIO.new("receipt"), filename: "receipt.pdf", content_type: "application/pdf")

      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.manager).call

      assert_equal(-2_600, entry.amount_cents)
      assert entry.finalized
      assert_equal @world.manager.user, entry.created_by
      assert_equal purchase.id, entry.metadata["purchase_id"]
      assert_equal "Order from Corner Store #A-1", entry.remark
      assert_equal budget.ledger_tags.to_a, entry.ledger_tags.to_a
      assert_equal [ "receipt.pdf" ], entry.receipts.map { |receipt| receipt.filename.to_s }
      assert_not_equal purchase.receipts.first.blob_id, entry.receipts.first.blob_id
      assert_not entry.split?
      assert_equal entry, purchase.reload.ledger_entry
      assert_equal(-2_600, @ledger.reload.balance_cents)
      assert_equal(-2_600, Budget.find(budget.id).actual_amount_cents)
    end
  end

  test "a purchase across two funding sources is split into an entry per source, each counting against its budget" do
    with_orders(@world) do
      build_budget = orders_budget(@world, "Build")
      grant_budget = orders_budget(@world, "Grant")
      general = FundingSource.create!(team: @world.robotics, name: "Build budget", budget: build_budget)
      grant = FundingSource.create!(team: @world.robotics, name: "Robot grant", kind: :restricted,
        restriction: "Robot parts only", budget: grant_budget)
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 30 }, { description: "Belt", price: 10 } ])
      order_request.update!(funding_source: general)
      order_request.order_lines.find_by(description: "Belt").update!(funding_source: grant)
      purchase = buy(@world, order_request.order_lines, shipping_cents: 400)

      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call

      assert_equal(-4_400, entry.amount_cents)
      assert entry.split?
      assert entry.fully_split?
      assert_empty entry.ledger_tags
      children = entry.child_entries.order(:remark).to_a
      assert_equal [ "Build budget", "Robot grant" ], children.map(&:remark)
      assert_equal [ -3_300, -1_100 ], children.map(&:amount_cents)
      assert_equal [ build_budget.ledger_tags.to_a, grant_budget.ledger_tags.to_a ], children.map { |child| child.ledger_tags.to_a }
      assert children.all? { |child| child.metadata["purchase_id"] == purchase.id }
      assert_equal(-4_400, @ledger.reload.balance_cents)
      assert_equal(-3_300, Budget.find(build_budget.id).actual_amount_cents)
      assert_equal(-1_100, Budget.find(grant_budget.id).actual_amount_cents)
    end
  end

  test "lines without a funding source get their own untagged part of a split" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request = approved_request(@world, lines: [ { description: "Gear", price: 30 }, { description: "Belt", price: 10 } ])
      order_request.order_lines.find_by(description: "Belt").update!(funding_source: source)
      purchase = buy(@world, order_request.order_lines)

      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call

      assert_equal [ "Build budget", "No funding source" ], entry.child_entries.map(&:remark).sort
      assert entry.child_entries.all? { |child| child.ledger_tags.empty? }
    end
  end

  test "a reimbursed purchase's entry names who to pay back" do
    with_orders(@world) do
      own_card = PaymentMethod.create!(name: "Own card", reimburse: true)
      order_request = approved_request(@world)
      purchase = buy(@world, order_request.order_lines, payment_method: own_card, reimburse_to_id: @world.buyer.id)

      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call

      assert_equal "Order from Corner Store, pay back Buyer Example", entry.remark
    end
  end

  test "someone who can't add entries to the ledger is refused and nothing is written" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines)

      error = assert_raises(Orders::Refused) do
        Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.buyer).call
      end
      assert_equal "You can't add entries to Robotics account.", error.message
      assert_nil purchase.reload.ledger_entry_id
      assert_equal 0, @ledger.ledger_entries.count
      assert_empty Orders::LedgerRecording.ledgers_for(@world.buyer)
      assert_equal [ @ledger ], Orders::LedgerRecording.ledgers_for(@world.manager)
    end
  end

  test "a purchase goes in the ledger once" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines)
      Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call

      assert_raises(Orders::Refused) { Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call }
      assert_equal 1, @ledger.ledger_entries.count
    end
  end

  test "nothing is recorded while the ledger is off" do
    with_orders(@world, feature_ledger: "false") do
      purchase = buy(@world, approved_request(@world).order_lines)

      assert_raises(Orders::Refused) { Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call }
      assert_empty Orders::LedgerRecording.ledgers_for(@world.admin)
      assert_equal 0, @ledger.ledger_entries.count
    end
  end

  test "with Budgets off the entry carries no budget tags and a source can't be linked" do
    with_orders(@world, feature_budgets: "false") do
      budget = orders_budget(@world, "Build")
      source = FundingSource.create!(team: @world.robotics, name: "Build", budget: budget)
      order_request = approved_request(@world)
      order_request.update!(funding_source: source)
      purchase = buy(@world, order_request.order_lines)

      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call

      assert_empty entry.ledger_tags
      assert_raises(Orders::Refused) { source.link_budget!(nil) }
      assert_equal budget, source.reload.budget
    end
  end

  test "deleting the ledger leaves its purchases Not in ledger" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines)
      Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call

      @ledger.destroy!

      assert_nil purchase.reload.ledger_entry_id
    end
  end

  test "deleting a Budget unlinks the funding sources linked to it" do
    with_orders(@world) do
      budget = orders_budget(@world, "Build")
      source = FundingSource.create!(team: @world.robotics, name: "Build", budget: budget)

      Budget.find(budget.id).destroy!

      assert_nil source.reload.budget_id
    end
  end
end
