require "test_helper"
require_relative "../../support/accounting_world"
require_relative "../../support/accounting_provider_contract"

class Accounting::QuickbooksGatewayTest < ActiveSupport::TestCase
  include AccountingWorld
  include Accounting::ProviderContract

  ALL_TYPES = Gateway::QuickbooksGateway::ENTITY_ROLES.keys.join(" ")

  setup do
    @gateway = create_quickbooks_gateway(synced_entities: ALL_TYPES)
    @invoices = {}
  end

  teardown { reset_fake_quickbooks }

  # With writing on, so the contract's create_charge check runs here too;
  # the writes raising while it's off are checked below.
  def provider_source
    @writing_gateway ||= create_quickbooks_gateway(synced_entities: ALL_TYPES, allow_create_charges: "true")
  end

  # QuickBooks answers a repeated requestid with the first invoice.
  def provider_billing_line
    fake_quickbooks.on(:post, "/invoice?") do |request|
      { "Invoice" => qbo_json("invoice_created")["Invoice"].merge("Id" => @invoices[request.query["requestid"]] ||= (201 + @invoices.size).to_s) }
    end
    person = create_linkable_person("Nancy", "Ward")
    run = AccountingBillingRun.create!(gateway: provider_source, created_by: person, item_external_id: "21", amount_cents: 45_000, status: "running")
    run.lines.create!(person: person, customer_external_id: "58", amount_cents: 45_000)
  end

  def provider_charge_count
    @invoices.size
  end

  test "397#10: writing is a setting, off by default, offered as a choice; off, the writes raise NotImplementedError" do
    input = provider_source.field_input(:allow_create_charges)
    assert_equal "Let GatherPack create invoices", input[:label]
    assert_equal [ "false", "true" ], input[:choices].map(&:last)
    assert_equal "true", input[:selected]
    assert_equal "false", @gateway.field_input(:allow_create_charges)[:selected]
    assert_nil @gateway.field_input(:client_id)
    assert_includes @gateway.fields, :allow_create_charges

    gateway = @gateway
    assert_not gateway.allow_create_charges?
    assert_empty gateway.capabilities & %i[ create_charges create_customers send_charges ]
    assert_raises(NotImplementedError) { gateway.create_charge(Struct.new(:request_id).new("a")) }
    assert_raises(NotImplementedError) { gateway.create_customer(Person.new, email: nil, request_id: "a") }
    assert_raises(NotImplementedError) { gateway.send_charge("201", email: "a@example.com") }
    assert_equal Accounting::Quickbooks::Client::WRITING_OFF, gateway.billing_problem
    assert_includes provider_source.capabilities, :send_charges
  end

  def provider_cases
    [
      [ "Customer", qbo_row("customers", "Customer"), { customer_external_id: "58", name: "Ward, Nancy", email: "nancy.ward@example.com", active: true } ],
      [ "Invoice", qbo_row("invoices", "Invoice"), { total_cents: 45_000, balance_cents: 15_000, due_on: Date.new(2026, 10, 1) } ],
      [ "SalesReceipt", qbo_row("sales_receipts", "SalesReceipt"), { total_cents: 2500, balance_cents: 0 } ],
      [ "Payment", qbo_row("payments", "Payment"), { total_cents: 25_000, unapplied_cents: 2000 } ],
      [ "CreditMemo", qbo_row("credit_memos", "CreditMemo"), { total_cents: 7500, balance_cents: 2500 } ],
      [ "RefundReceipt", qbo_row("refund_receipts", "RefundReceipt"), { total_cents: 1000 } ],
      [ "Item", qbo_row("items", "Item"), { name: "Dues", active: true } ],
      [ "Class", qbo_row("classes", "Class"), { name: "Programs" } ],
      [ "Department", { "Id" => "2", "SyncToken" => "0", "Name" => "North", "Active" => true }, { name: "North" } ]
    ]
  end

  test "a customer's columns, with the reference from the chosen field" do
    @gateway.update!(match_field_path: "Notes")
    columns = @gateway.normalize("Customer", qbo_row("customers", "Customer"))

    assert_equal "per_nancy", columns[:reference]
    assert_nil columns[:parent_external_id]
    assert_equal "https://app.sandbox.qbo.intuit.com/app/customerdetail?nameId=58", columns[:external_url]

    sub = @gateway.normalize("Customer", qbo_row("customers", "Customer", 1))
    assert_equal "58", sub[:parent_external_id]
    assert_equal false, sub[:active]
  end

  test "an invoice's lines include those inside groups, and its classes come from the invoice and its lines" do
    columns = @gateway.normalize("Invoice", qbo_row("invoices", "Invoice"))

    assert_equal [
      { "item_id" => "21", "class_id" => "5000000000000000022", "amount_cents" => 40_000 },
      { "item_id" => "22", "class_id" => nil, "amount_cents" => 3000 },
      { "item_id" => "23", "class_id" => nil, "amount_cents" => 2000 }
    ], columns[:lines]
    assert_equal %w[ 21 22 23 ], columns[:item_ids]
    assert_equal %w[ 5000000000000000011 5000000000000000022 ], columns[:class_ids]
    assert_equal %w[ 2 ], columns[:location_ids]
    assert_equal "58", columns[:customer_external_id]
    assert_equal "1042", columns[:number]
    assert_equal Date.new(2026, 9, 1), columns[:txn_date]
    assert_not columns[:voided]
  end

  test "an invoice's label names its number and first item, never its notes" do
    columns = @gateway.normalize("Invoice", qbo_row("invoices", "Invoice"))

    assert_equal "Invoice 1042 · Dues and 1 more", columns[:public_label]
    assert_equal "Hardship discussed with treasurer\nThank you!", columns[:description]
  end

  test "renamed role labels are used" do
    @gateway.update!(role_labels: { "charge" => "Bill", "credit" => "Allowance" })

    assert_equal "Bill 1043 · Dues", @gateway.normalize("Invoice", qbo_row("invoices", "Invoice", 1))[:public_label]
    assert_equal "Allowance", @gateway.normalize("CreditMemo", qbo_row("credit_memos", "CreditMemo"))[:public_label]
    assert_equal "Payment", @gateway.normalize("Payment", qbo_row("payments", "Payment"))[:public_label]
  end

  test "a voided invoice is marked voided" do
    columns = @gateway.normalize("Invoice", qbo_row("invoices", "Invoice", 1))

    assert columns[:voided]
    assert_equal 0, columns[:total_cents]
  end

  test "the pay link and deep link" do
    columns = @gateway.normalize("Invoice", qbo_row("invoices", "Invoice"))

    assert_equal "https://connect.intuit.com/portal/app/CommerceNetwork/view/scs-v1-abc", columns[:pay_url]
    assert_equal "https://app.sandbox.qbo.intuit.com/app/invoice?txnId=130", columns[:external_url]

    @gateway.update!(environment: "production")
    assert_equal "https://app.qbo.intuit.com/app/invoice?txnId=130", @gateway.normalize("Invoice", qbo_row("invoices", "Invoice"))[:external_url]
  end

  test "a payment is applied to its invoices, with what's left unapplied" do
    columns = @gateway.normalize("Payment", qbo_row("payments", "Payment"))

    assert_equal [ { "external_id" => "130", "amount_cents" => 23_000 } ], columns[:applied_to]
    assert_equal 2000, columns[:unapplied_cents]
    assert_equal "Payment", columns[:public_label]
    assert_equal "Scholarship fund top-up", columns[:description]
  end

  test "a payment that also applies a credit memo counts only its money against the invoice" do
    columns = @gateway.normalize("Payment", qbo_row("payments", "Payment", 1))

    assert_equal [ { "external_id" => "130", "amount_cents" => 2000 } ], columns[:applied_to]
    assert_equal 0, columns[:unapplied_cents]
  end

  test "a credit memo's balance is what's left to apply, and its label is only Credit" do
    columns = @gateway.normalize("CreditMemo", qbo_row("credit_memos", "CreditMemo"))

    assert_equal 2500, columns[:balance_cents]
    assert_equal 2500, columns[:unapplied_cents]
    assert_equal "Credit", columns[:public_label]
    assert_equal "Hardship scholarship", columns[:description]
  end

  test "a sales receipt has no balance and a receipt label" do
    columns = @gateway.normalize("SalesReceipt", qbo_row("sales_receipts", "SalesReceipt"))

    assert_equal "Receipt SR-3", columns[:public_label]
    assert_equal %w[ 22 ], columns[:item_ids]
    assert_nil columns[:pay_url]
  end

  test "a refund" do
    columns = @gateway.normalize("RefundReceipt", qbo_row("refund_receipts", "RefundReceipt"))

    assert_equal "Refund", columns[:public_label]
    assert_equal "58", columns[:customer_external_id]
  end

  test "revision is the sync token" do
    assert_equal "2", @gateway.revision("Invoice", qbo_row("invoices", "Invoice"))
    assert_equal "130", @gateway.external_id("Invoice", qbo_row("invoices", "Invoice"))
  end

  test "only the chosen types are copied" do
    @gateway.update!(synced_entities: "Customer Invoice")

    assert_equal({ "Customer" => :customer, "Invoice" => :charge }, @gateway.entity_types)
    @gateway.synced_entities = "Customer Vendor"
    assert_not @gateway.valid?
  end

  test "notifications need the verifier token" do
    assert_includes @gateway.capabilities, :notifications
    @gateway.update!(webhook_verifier_token: "")

    assert_not_includes @gateway.reload.capabilities, :notifications
    assert_includes @gateway.capabilities, :change_feed
    assert_not_includes @gateway.capabilities, :create_charges
  end

  test "connection state" do
    assert_equal :ok, @gateway.connection_state
    @gateway.record_state!(connection_status: "needs_reconnect")
    assert_equal :needs_attention, @gateway.connection_state
    assert_not @gateway.syncable?
    assert_equal :not_connected, create_quickbooks_gateway(connected: false).connection_state
  end

  test "state written by the system doesn't make an audit log entry or fire gateway hooks" do
    Hook.create!(name: "Gateway changed", event: "gateways - update", code: "raise 'fired'")

    assert_no_difference -> { AuditLog.count } do
      @gateway.record_state!(last_error: "Boom", last_full_sync_at: Time.current)
    end
    assert_equal "Boom", @gateway.reload.last_error
  end

  test "calls are counted per month" do
    2.times { @gateway.record_call! }
    assert_equal 2, @gateway.reload.calls_in_month

    travel 1.month do
      assert_equal 0, @gateway.reload.calls_in_month
      @gateway.record_call!
      assert_equal 1, @gateway.reload.calls_in_month
    end
  end

  test "the reconnect warning shows within 30 days of the sign-in running out" do
    assert_nil @gateway.reconnect_by

    @gateway.accounting_credential.update!(refresh_token_expires_at: 20.days.from_now)
    assert_equal @gateway.accounting_credential.refresh_token_expires_at, @gateway.reload.reconnect_by
  end

  test "deleting the gateway deletes its records and tokens" do
    @gateway.accounting_records.create!(entity_type: "Customer", external_id: "58", role: "customer", data: {})

    assert_difference -> { AccountingRecord.count } => -1, -> { AccountingCredential.count } => -1 do
      @gateway.destroy!
    end
  end

  test "tokens are stored encrypted" do
    raw = AccountingCredential.connection.select_value("SELECT refresh_token FROM accounting_credentials WHERE id = #{AccountingCredential.connection.quote(@gateway.accounting_credential.id)}")

    assert_not_includes raw, "refresh-token"
    assert_equal "refresh-token", @gateway.accounting_credential.reload.refresh_token
  end
end
