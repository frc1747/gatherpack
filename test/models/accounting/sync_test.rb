require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::SyncTest < ActiveSupport::TestCase
  include AccountingWorld

  setup do
    @gateway = create_quickbooks_gateway(synced_entities: "Customer Invoice Payment CreditMemo Item")
    @fake = fake_quickbooks
    @sync = Accounting::Sync.new(@gateway)
  end

  teardown { reset_fake_quickbooks }

  test "a full sync copies every synced type, inactive customers included" do
    answer_queries
    @sync.full

    records = @gateway.accounting_records
    assert_equal({ "charge" => 2, "credit" => 1, "customer" => 2, "item" => 2, "payment" => 2 }, records.group(:role).count)
    customer_query = @fake.api_requests.map { |request| request.query["query"] }.find { |query| query.include?("from Customer") }
    assert_includes customer_query, "Active IN (true, false)"
    invoice = records.find_by(entity_type: "Invoice", external_id: "130")
    assert_equal 15_000, invoice.balance_cents
    assert_equal "2", invoice.revision
    assert_equal qbo_row("invoices", "Invoice"), invoice.data
    assert @gateway.reload.last_full_sync_time
    assert @gateway.last_change_check_time
  end

  test "a full sync pages past 1000 records" do
    big = AccountingWorld::FakeTransport.new.on(:get, "/query") do |request|
      statement = request.query["query"]
      next { "QueryResponse" => {} } unless statement.include?("from Customer")

      start = statement[/STARTPOSITION (\d+)/, 1].to_i
      count = start == 1 ? 1000 : 5
      { "QueryResponse" => { "Customer" => Array.new(count) { |i| { "Id" => (start + i).to_s, "SyncToken" => "0", "DisplayName" => "Customer #{start + i}" } } } }
    end
    Accounting::Quickbooks::Client.transport = big

    Accounting::Sync.new(Gateway.find(@gateway.id)).full
    assert_equal 1005, @gateway.accounting_records.where(role: "customer").count
  end

  test "a full sync marks records it no longer sees deleted" do
    answer_queries
    @sync.full
    gone = @gateway.accounting_records.find_by(entity_type: "Invoice", external_id: "131")

    reset_fake_quickbooks
    only_first = qbo_json("invoices").tap { |json| json["QueryResponse"]["Invoice"].pop }
    fake_quickbooks.on(:get, "/query") do |request|
      entity = request.query["query"][/from (\w+)/, 1]
      entity == "Invoice" ? only_first : qbo_fixture({ "Customer" => "customers", "Payment" => "payments", "CreditMemo" => "credit_memos", "Item" => "items" }.fetch(entity))
    end
    Accounting::Sync.new(Gateway.find(@gateway.id)).full

    assert gone.reload.deleted?
    assert_not @gateway.accounting_records.find_by(external_id: "130", entity_type: "Invoice").deleted?
  end

  test "a credit memo's use is filled in from the payment that applies it" do
    answer_queries
    @sync.full

    credit = @gateway.accounting_records.find_by(entity_type: "CreditMemo", external_id: "150")
    assert_equal [ { "external_id" => "130", "amount_cents" => 5000 } ], credit.applied_to
  end

  test "a credit memo's hooks see where it was applied" do
    @sync.upsert("Payment", qbo_row("payments", "Payment", 1))
    Hook.create!(name: "Credit used", event: "accounting_records - create", code: "model.gateway.record_state!(credit_applied: model.applied_to) if model.role == 'credit'")

    @sync.upsert("CreditMemo", qbo_row("credit_memos", "CreditMemo"))

    assert_equal [ { "external_id" => "130", "amount_cents" => 5000 } ], @gateway.reload.configuration["credit_applied"]
  end

  test "a credit memo changed in QuickBooks keeps its applied_to through the hooked save" do
    @sync.upsert("Payment", qbo_row("payments", "Payment", 1))
    @sync.upsert("CreditMemo", qbo_row("credit_memos", "CreditMemo"))
    Hook.create!(name: "Credit changed", event: "accounting_records - update", code: "model.gateway.record_state!(credit_applied: model.applied_to)")

    @sync.upsert("CreditMemo", qbo_row("credit_memos", "CreditMemo").merge("SyncToken" => "2"))

    assert_equal [ { "external_id" => "130", "amount_cents" => 5000 } ], @gateway.reload.configuration["credit_applied"]
  end

  test "an unchanged revision isn't saved again and fires no hooks" do
    answer_queries
    @sync.full
    Hook.create!(name: "Watch records", event: "accounting_records - update", code: "raise 'should not fire'")
    before = @gateway.accounting_records.pluck(:id, :updated_at).to_h

    assert_empty Accounting::Sync.new(Gateway.find(@gateway.id)).full
    assert_equal before, @gateway.accounting_records.pluck(:id, :updated_at).to_h
  end

  test "a changed revision is saved and fires the record hooks" do
    hook_code = "model.gateway.record_state!(hooked: [ model.external_id, model.balance_cents ])"
    Hook.create!(name: "New records", event: "accounting_records - create", code: hook_code)
    Hook.create!(name: "Changed records", event: "accounting_records - update", code: hook_code)
    @fake.on(:get, "/invoice/130", body: qbo_fixture("invoice_130"))

    @sync.upsert("Invoice", qbo_row("invoices", "Invoice"))
    assert_equal [ "130", 15_000 ], @gateway.reload.configuration["hooked"]

    @gateway.record_state!(hooked: nil)
    @sync.fetch("Invoice", "130")
    assert_equal [ "130", 10_000 ], @gateway.reload.configuration["hooked"]
    assert_equal "4", @gateway.accounting_records.find_by(external_id: "130").revision
  end

  test "a column the new revision leaves out is cleared" do
    @sync.upsert("Invoice", qbo_row("invoices", "Invoice"))
    changed = qbo_row("invoices", "Invoice").merge("SyncToken" => "9").except("InvoiceLink", "DepartmentRef")
    @sync.upsert("Invoice", changed)

    record = @gateway.accounting_records.find_by(external_id: "130")
    assert_nil record.pay_url
    assert_equal [], record.location_ids
  end

  test "the changes job reads changes since the last check and moves the check on" do
    since = 2.hours.ago.change(usec: 0)
    @gateway.record_state!(last_change_check_at: since)
    @sync.upsert("Invoice", qbo_row("invoices", "Invoice", 1))
    @fake.on(:get, "/cdc", body: qbo_fixture("cdc"))

    freeze_time do
      @sync.changes

      assert_equal since.utc.iso8601, @fake.api_requests.last.query["changedSince"]
      assert_equal "Customer,Invoice,Payment,CreditMemo,Item", @fake.api_requests.last.query["entities"]
      assert_equal (Time.current - Accounting::Sync::OVERLAP).iso8601, @gateway.reload.last_change_check_time.iso8601
    end
    assert_equal 0, @gateway.accounting_records.find_by(external_id: "130").balance_cents
    assert @gateway.accounting_records.find_by(external_id: "131").deleted?
    assert_equal 15_000, @gateway.accounting_records.find_by(entity_type: "Payment", external_id: "142").total_cents
    assert_empty @fake.api_requests.select { |request| request.url.include?("/query") }
  end

  test "the changes job does a full sync when the last check is past the 30-day window or never happened" do
    answer_queries
    @gateway.record_state!(last_change_check_at: 31.days.ago)

    @sync.changes
    assert @fake.api_requests.any? { |request| request.url.include?("/query") }
    assert_empty @fake.api_requests.select { |request| request.url.include?("/cdc") }
    assert @gateway.reload.last_full_sync_time
  end

  test "a record the source no longer has is marked deleted when fetched" do
    @sync.upsert("Invoice", qbo_row("invoices", "Invoice", 1))
    @fake.on(:get, "/invoice/131", status: 400, body: qbo_fixture("not_found"))

    @sync.fetch("Invoice", "131")
    assert @gateway.accounting_records.find_by(external_id: "131").deleted?
  end

  test "an unsynced type isn't fetched" do
    assert_empty @sync.fetch("RefundReceipt", "170")
    assert_empty @fake.requests
  end
end
