require "test_helper"
require "support/orders_world"
require "support/orders_ledger_world"

# Orders with the Ledger and Budgets features (spec §6): Record in ledger on
# a purchase or later, the Not in ledger list, a funding source's Budget in
# the funding picture, and nothing of either while it's off.
class Orders::LedgerControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld
  include OrdersLedgerWorld

  setup do
    @world = build_orders_world
    @ledger = orders_ledger(@world)
  end

  test "a buyer who may add entries records the purchase in the ledger as they record it" do
    with_orders(@world) do
      line = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ]).order_lines.first
      sign_in @world.manager.user

      get new_orders_purchase_url(line_ids: [ line.id ])
      assert_select "#ledger_choice select[name=ledger_id] option", "Robotics account"

      post orders_purchases_url, params: { line_ids: [ line.id ], record_in_ledger: "1", ledger_id: @ledger.id,
        purchase: { ordered_on: Date.current.iso8601, payment_method_id: payment_method("Team card").id, shipping: "2.00" } }

      purchase = Purchase.order(:created_at).last
      assert_redirected_to orders_purchase_url(purchase)
      entry = purchase.ledger_entry
      assert_equal(-1_200, entry.amount_cents)
      assert_equal @ledger, entry.ledger

      follow_redirect!
      assert_select "#purchase_ledger a[href='#{ledger_ledger_entry_path(@ledger, entry)}']", /Robotics account/
    end
  end

  test "recording in the ledger with the purchase copies the receipt the buyer attached" do
    with_orders(@world) do
      line = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ]).order_lines.first
      sign_in @world.manager.user

      receipt = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 receipt"), "application/pdf", original_filename: "receipt.pdf")
      post orders_purchases_url, params: { line_ids: [ line.id ], record_in_ledger: "1", ledger_id: @ledger.id,
        purchase: { ordered_on: Date.current.iso8601, payment_method_id: payment_method("Team card").id, receipts: [ receipt ] } }

      purchase = Purchase.order(:created_at).last
      assert_redirected_to orders_purchase_url(purchase)
      entry = purchase.ledger_entry
      assert_equal [ "receipt.pdf" ], entry.receipts.map { |file| file.filename.to_s }
      assert_equal "%PDF-1.4 receipt", entry.receipts.first.download
      assert_equal "%PDF-1.4 receipt", purchase.receipts.first.download
    end
  end

  test "deleting a purchase's ledger entry puts the purchase back to Not in ledger" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines)
      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call
      sign_in @world.manager.user

      delete ledger_ledger_entry_url(@ledger, entry)

      assert_redirected_to ledger_url(@ledger)
      assert_not LedgerEntry.exists?(entry.id)
      assert_nil purchase.reload.ledger_entry_id
      get orders_purchase_url(purchase)
      assert_select "#purchase_ledger", /Not in ledger/
      assert_select "#purchase_ledger form", 1
    end
  end

  test "a buyer without ledger permission gets no choice, and a forged one is refused without recording the purchase" do
    with_orders(@world) do
      line = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ]).order_lines.first
      sign_in @world.buyer.user

      get new_orders_purchase_url(line_ids: [ line.id ])
      assert_select "#ledger_choice", false

      post orders_purchases_url, params: { line_ids: [ line.id ], record_in_ledger: "1", ledger_id: @ledger.id,
        purchase: { ordered_on: Date.current.iso8601, payment_method_id: payment_method("Team card").id } }

      assert_equal "You can't add entries to Robotics account.", flash[:alert]
      assert_nil line.reload.purchase_id
      assert_equal 0, Purchase.count
      assert_equal 0, @ledger.ledger_entries.count
    end
  end

  test "Not in ledger lists purchases without an entry, and a treasurer records one later" do
    with_orders(@world) do
      recorded = buy(@world, approved_request(@world, title: "Recorded").order_lines)
      Orders::RecordInLedger.new(recorded, ledger: @ledger, by: @world.admin).call
      waiting = buy(@world, approved_request(@world, title: "Waiting").order_lines)
      sign_in @world.manager.user

      get orders_purchases_url(not_in_ledger: 1)
      assert_select "h1", /not in ledger/
      assert_select "a[href='#{orders_purchase_path(waiting)}']", 1
      assert_select "a[href='#{orders_purchase_path(recorded)}']", 0

      get orders_purchase_url(waiting)
      assert_select "#purchase_ledger", /Not in ledger/
      assert_select "#purchase_ledger form button, #purchase_ledger form input[type=submit]", 1

      post orders_purchase_ledger_entry_url(waiting), params: { ledger_id: @ledger.id }
      assert_redirected_to orders_purchase_url(waiting)
      assert_equal "Recorded in Robotics account.", flash[:notice]
      assert_equal(-waiting.total_cents, waiting.reload.ledger_entry.amount_cents)
    end
  end

  test "the buyer sees Not in ledger but can't record it later without ledger permission" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines)
      sign_in @world.buyer.user

      get orders_purchase_url(purchase)
      assert_select "#purchase_ledger", /Not in ledger/
      assert_select "#purchase_ledger form", 0

      post orders_purchase_ledger_entry_url(purchase), params: { ledger_id: @ledger.id }
      assert_redirected_to root_url
      assert_nil purchase.reload.ledger_entry_id
    end
  end

  test "the ledger entry page links back to its purchase" do
    with_orders(@world) do
      purchase = buy(@world, approved_request(@world).order_lines, vendor_order_number: "A-7")
      entry = Orders::RecordInLedger.new(purchase, ledger: @ledger, by: @world.admin).call
      sign_in @world.admin.user

      get ledger_ledger_entry_url(@ledger, entry)
      assert_response :success
      assert_select "#ledger_entry_purchase a[href='#{orders_purchase_path(purchase)}']", "Corner Store A-7"
    end
  end

  test "with the ledger off, nothing ledger-related shows and recording is turned away" do
    with_orders(@world, feature_ledger: "false") do
      line = approved_request(@world, lines: [ { description: "Gear", price: 10, vendor_id: @world.preferred_vendor.id } ]).order_lines.first
      purchase = buy(@world, approved_request(@world).order_lines)
      sign_in @world.manager.user

      get new_orders_purchase_url(line_ids: [ line.id ])
      assert_select "#ledger_choice", false

      get orders_purchases_url
      assert_no_match "ledger", response.body.downcase.gsub(/ledgers_path|\/ledgers/, "")
      assert_select "a", text: "Not in ledger", count: 0

      get orders_purchase_url(purchase)
      assert_select "#purchase_ledger", false

      post orders_purchase_ledger_entry_url(purchase), params: { ledger_id: @ledger.id }
      assert_redirected_to orders_purchases_url
      assert_nil purchase.reload.ledger_entry_id

      post orders_purchases_url, params: { line_ids: [ line.id ], record_in_ledger: "1", ledger_id: @ledger.id,
        purchase: { ordered_on: Date.current.iso8601, payment_method_id: payment_method("Team card").id } }
      assert line.reload.ordered?
      assert_equal 0, @ledger.ledger_entries.count
    end
  end

  test "an approver sees a linked Budget's amount and ledger spending in the funding picture" do
    with_orders(@world) do
      budget = orders_budget(@world, "Build", amount_cents: 50_000)
      LedgerEntry.create!(ledger: @ledger, created_by: @world.admin.user, amount_cents: -12_000, remark: "Travel",
        ledger_tag_ids: budget.ledger_tag_ids)
      source = FundingSource.create!(team: @world.robotics, name: "Build budget", amount_cents: 40_000, budget: budget)
      order_request = submitted_request(@world)
      order_request.update!(funding_source: source)
      sign_in @world.mentor.user

      get orders_request_url(order_request)
      assert_select ".orders-decision-funding .orders-funding-budget" do
        assert_select "dd", /\$500\.00/
        assert_select "dd", /\$120\.00/
        assert_select "dd", /\$380\.00/
      end
      assert_select ".orders-decision-funding a", text: /budget/i, count: 0
    end
  end

  test "with Budgets off the funding picture shows no budget and the link page is turned away" do
    with_orders(@world, feature_budgets: "false") do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget", budget: orders_budget(@world, "Build"))
      order_request = submitted_request(@world)
      order_request.update!(funding_source: source)
      sign_in @world.admin.user

      get orders_request_url(order_request)
      assert_select ".orders-decision-funding", /Build budget/
      assert_select ".orders-funding-budget", 0
      assert_select ".orders-decision-funding a", text: /budget/i, count: 0

      get edit_orders_funding_source_budget_url(source)
      assert_redirected_to orders_requests_url
    end
  end

  test "a team manager deciding a request can link its source to a Budget" do
    with_orders(@world) do
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      order_request = submitted_request(@world)
      order_request.update!(funding_source: source)
      sign_in @world.manager.user

      get orders_request_url(order_request)
      assert_select ".orders-decision-funding a[href='#{edit_orders_funding_source_budget_path(source)}']", "Link a budget"
    end
  end

  test "a funding manager links a source to a Budget and unlinks it" do
    with_orders(@world) do
      budget = orders_budget(@world, "Build")
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      sign_in @world.funding_manager.user

      get edit_orders_funding_source_budget_url(source)
      assert_response :success
      assert_select "select[name='funding_source[budget_id]'] option[value='#{budget.id}']"

      patch orders_funding_source_budget_url(source), params: { funding_source: { budget_id: budget.id } }
      assert_redirected_to edit_orders_funding_source_budget_url(source)
      assert_equal budget, source.reload.budget

      patch orders_funding_source_budget_url(source), params: { funding_source: { budget_id: "" } }
      assert_nil source.reload.budget
    end
  end

  test "a funding manager can keep a Budget they can't list themselves" do
    with_orders(@world) do
      club_manager = orders_person("Leader", teams: { @world.club => true })
      budget = orders_budget(@world, "Build")
      source = FundingSource.create!(team: @world.robotics, name: "Build budget", budget: budget)
      sign_in club_manager.user

      get edit_orders_funding_source_budget_url(source)
      assert_select "select[name='funding_source[budget_id]'] option[selected][value='#{budget.id}']"

      patch orders_funding_source_budget_url(source), params: { funding_source: { budget_id: budget.id } }
      assert_redirected_to edit_orders_funding_source_budget_url(source)
      assert_nil flash[:alert]
      assert_equal budget, source.reload.budget

      other = orders_budget(@world, "Other")
      patch orders_funding_source_budget_url(source), params: { funding_source: { budget_id: other.id } }
      assert_equal "Choose one of the budgets listed.", flash[:alert]
      assert_equal budget, source.reload.budget
    end
  end

  test "someone who doesn't manage funding can't link a Budget" do
    with_orders(@world) do
      budget = orders_budget(@world, "Build")
      source = FundingSource.create!(team: @world.robotics, name: "Build budget")
      sign_in @world.mentor.user

      get edit_orders_funding_source_budget_url(source)
      assert_redirected_to root_url

      patch orders_funding_source_budget_url(source), params: { funding_source: { budget_id: budget.id } }
      assert_nil source.reload.budget
    end
  end
end
