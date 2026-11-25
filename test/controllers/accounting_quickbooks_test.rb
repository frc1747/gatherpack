require "test_helper"
require_relative "../support/accounting_world"

class AccountingQuickbooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include AccountingWorld

  setup do
    host! "localhost"
    @gateway = create_quickbooks_gateway(connected: false)
    @architect = create_accounting_user("Architect", admin: true, architect: true)
    @admin = create_accounting_user("Admin", admin: true)
    @builder = create_accounting_user("Builder", architect: true)
    @member = create_accounting_user("Member")
    @fake = fake_quickbooks
  end

  teardown { reset_fake_quickbooks }

  # -- Connecting --

  test "connect sends an architect to Intuit with a state kept in the session" do
    sign_in @architect
    with_accounting { get connect_accounting_connection_path(@gateway) }

    location = URI(response.location)
    assert_equal "appcenter.intuit.com", location.host
    query = Rack::Utils.parse_query(location.query)
    assert_equal "http://localhost/accounting/quickbooks/callback", query["redirect_uri"]
    assert query["state"].present?
  end

  test "the callback saves the tokens, the company and queues a full sync" do
    sign_in @architect
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))
    @fake.on(:get, "/companyinfo/", body: qbo_fixture("company_info"))

    with_accounting do
      get connect_accounting_connection_path(@gateway)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]

      assert_enqueued_with(job: Accounting::FullSyncJob) do
        get accounting_quickbooks_callback_path(code: "auth-code", state: state, realmId: AccountingWorld::REALM)
      end
    end

    assert_redirected_to gateway_path(@gateway)
    @gateway.reload
    assert_equal "connected", @gateway.connection_status
    assert_equal AccountingWorld::REALM, @gateway.realm_id
    assert_equal "Northwind Robotics Club", @gateway.company_name
    assert_equal "rotated-refresh-token", @gateway.accounting_credential.refresh_token
  end

  test "a callback with the wrong state is refused" do
    sign_in @architect

    with_accounting do
      get connect_accounting_connection_path(@gateway)
      get accounting_quickbooks_callback_path(code: "auth-code", state: "forged", realmId: AccountingWorld::REALM)
    end

    assert_redirected_to gateway_path(@gateway)
    assert_empty @fake.requests
    assert_nil @gateway.reload.accounting_credential
  end

  test "a callback nobody started is refused" do
    sign_in @architect
    with_accounting { get accounting_quickbooks_callback_path(code: "auth-code", state: "x", realmId: AccountingWorld::REALM) }

    assert_redirected_to gateways_path
    assert_empty @fake.requests
  end

  test "reconnecting to different books is refused" do
    sign_in @architect
    @gateway.record_state!(realm_id: "4620816365000000")

    with_accounting do
      get connect_accounting_connection_path(@gateway)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      get accounting_quickbooks_callback_path(code: "auth-code", state: state, realmId: AccountingWorld::REALM)
    end

    assert_match "different books", flash[:alert]
    assert_empty @fake.requests
  end

  test "disconnect asks first, and changes nothing until confirmed" do
    gateway = create_quickbooks_gateway
    sign_in @architect

    with_accounting { get disconnect_accounting_connection_path(gateway) }

    assert_response :success
    assert_select "h1", "Disconnect QuickBooks?"
    assert_match "Records stay; reconnect any time.", response.body
    assert_select "a[href=?]", gateway_path(gateway), text: "Cancel"
    assert_select "form[action=?][method=post] button", disconnect_accounting_connection_path(gateway), text: "Disconnect"
    assert_equal "connected", gateway.reload.connection_status
    assert gateway.accounting_credential
    assert_empty @fake.requests
  end

  test "disconnect revokes and deletes the tokens and keeps the records" do
    gateway = create_quickbooks_gateway
    gateway.accounting_records.create!(entity_type: "Customer", external_id: "58", role: "customer", data: {})
    @fake.on(:post, Accounting::Quickbooks::REVOKE_URL, body: "")
    sign_in @architect

    with_accounting { post disconnect_accounting_connection_path(gateway) }

    assert_redirected_to gateway_path(gateway)
    assert_equal "disconnected", gateway.reload.connection_status
    assert_nil gateway.accounting_credential
    assert_equal 1, gateway.accounting_records.count
    assert_equal Accounting::Quickbooks::REVOKE_URL, @fake.requests.last.url
  end

  test "only architects connect and disconnect" do
    gateway = create_quickbooks_gateway
    sign_in @admin

    with_accounting do
      get connect_accounting_connection_path(@gateway)
      assert_no_match "intuit.com", response.location.to_s
      get disconnect_accounting_connection_path(gateway)
      assert_response :redirect
      post disconnect_accounting_connection_path(gateway)
    end

    assert_equal "connected", gateway.reload.connection_status
    assert_empty @fake.requests
  end

  # -- Syncing and records --

  test "admins can sync now and copy everything again" do
    gateway = create_quickbooks_gateway
    sign_in @admin

    with_accounting do
      assert_enqueued_with(job: Accounting::ChangesJob) { post sync_accounting_connection_path(gateway) }
      assert_enqueued_with(job: Accounting::FullSyncJob) { post full_sync_accounting_connection_path(gateway) }
    end
    assert_redirected_to accounting_connection_records_path(gateway)
  end

  test "an architect who isn't an admin can open Records and sync from there" do
    gateway = create_quickbooks_gateway
    Accounting::Sync.new(gateway).upsert("Invoice", qbo_row("invoices", "Invoice"))
    sign_in @builder

    with_accounting do
      get gateway_path(gateway)
      assert_select "a[href=?]", accounting_connection_records_path(gateway), text: "Records"

      get accounting_connection_records_path(gateway)
      assert_response :success
      assert_select "td", text: /Invoice 1042/
      assert_select "form[action=?] button", sync_accounting_connection_path(gateway), text: "Sync now"

      assert_enqueued_with(job: Accounting::ChangesJob) { post sync_accounting_connection_path(gateway) }
    end
  end

  test "admins don't see the sync buttons for a source that isn't connected" do
    sign_in @admin
    with_accounting { get accounting_connection_records_path(@gateway) }

    assert_response :success
    assert_select "button", text: "Sync now", count: 0
  end

  test "members can't sync or see records" do
    gateway = create_quickbooks_gateway
    gateway.accounting_records.create!(entity_type: "Invoice", external_id: "130", role: "charge", data: {}, description: "Hardship note")
    sign_in @member

    with_accounting do
      assert_no_enqueued_jobs { post sync_accounting_connection_path(gateway) }
      get accounting_connection_records_path(gateway)
      assert_no_match "Hardship note", response.body
      get accounting_connection_record_path(gateway, gateway.accounting_records.first)
      assert_no_match "Hardship note", response.body
    end
  end

  test "the records page lists the copy, filtered by role, customer and date" do
    gateway = create_quickbooks_gateway
    sync = Accounting::Sync.new(gateway)
    sync.upsert("Customer", qbo_row("customers", "Customer"))
    sync.upsert("Invoice", qbo_row("invoices", "Invoice"))
    sync.upsert("Payment", qbo_row("payments", "Payment"))
    sign_in @admin

    with_accounting do
      get accounting_connection_records_path(gateway)
      assert_response :success
      assert_select "td", text: /Invoice 1042/
      assert_select "td", text: "Ward, Nancy"
      assert_select "a[href=?]", "https://app.sandbox.qbo.intuit.com/app/invoice?txnId=130"

      get accounting_connection_records_path(gateway, role: "payment")
      assert_select "td", text: /Invoice 1042/, count: 0
      assert_select "td", text: /Payment/

      get accounting_connection_records_path(gateway, customer: "58", from: "2026-09-10", to: "2026-09-30")
      assert_select "td", text: /Invoice 1042/, count: 0
      assert_select "td", text: /Payment/
    end
  end

  test "a record's page shows its columns and the raw record" do
    gateway = create_quickbooks_gateway
    record = Accounting::Sync.new(gateway).upsert("Invoice", qbo_row("invoices", "Invoice"))
    sign_in @admin

    with_accounting { get accounting_connection_record_path(gateway, record) }

    assert_response :success
    assert_match "Hardship discussed with treasurer", response.body
    assert_match "&quot;DocNumber&quot;: &quot;1042&quot;", response.body
    assert_match "Open in QuickBooks", response.body
  end

  test "the gateway page shows the connection and what GatherPack may do" do
    gateway = create_quickbooks_gateway
    sign_in @architect

    with_accounting { get gateway_path(gateway) }

    assert_response :success
    assert_match "It never changes, voids or deletes anything and never records payments.", response.body
    assert_select "a", text: "Reconnect"
    assert_select "a[href=?]", disconnect_accounting_connection_path(gateway), text: "Disconnect"
    assert_select "button", text: "Sync now", count: 0
    assert_select "button", text: "Copy everything again", count: 0
  end

  test "397#10: the gateway page says what writing allows, on and off, and the edit page offers the setting" do
    gateway = create_quickbooks_gateway
    sign_in @architect

    with_accounting { get gateway_path(gateway) }
    assert_match "Turn on \"Let GatherPack create invoices\" to bill people from GatherPack.", response.body
    assert_no_match "it can also create new invoices and customers", response.body

    gateway.update!(allow_create_charges: "true")
    with_accounting { get gateway_path(gateway) }
    assert_match "With \"Let GatherPack create invoices\" on, it can also create new invoices and customers, " \
      "and email the invoices it created.", response.body
    assert_no_match "Turn on \"Let GatherPack create invoices\"", response.body

    with_accounting { get edit_gateway_path(gateway) }
    assert_select "label[for=gateway_allow_create_charges]", text: "Let GatherPack create invoices"
    assert_select "select[name='gateway[allow_create_charges]'] option[selected][value=true]"
  end

  test "the button says Reconnect for books connected before" do
    sign_in @architect
    with_accounting do
      get gateway_path(@gateway)
      assert_select "a", text: "Connect to QuickBooks"

      gateway = create_quickbooks_gateway
      gateway.needs_reconnect!("Refused")
      get gateway_path(gateway)
      assert_select "a", text: "Reconnect"
      assert_select "a", text: "Connect to QuickBooks", count: 0

      gateway.record_state!(connection_status: "disconnected")
      get gateway_path(gateway)
      assert_select "a", text: "Reconnect"
    end
  end

  # -- Notifications --

  test "a signed notification is accepted and its records fetched" do
    gateway = create_quickbooks_gateway
    Accounting::Sync.new(gateway).upsert("Invoice", qbo_row("invoices", "Invoice", 1))
    body = qbo_fixture("webhook")

    with_accounting do
      assert_enqueued_with(job: ProcessGatewayWebhookJob) do
        post webhook_gateway_path(gateway), params: body, headers: { "Content-Type" => "application/json", "intuit-signature" => sign_webhook(body) }
      end
      assert_response :no_content

      perform_enqueued_jobs(only: ProcessGatewayWebhookJob)
    end

    fetched = enqueued_jobs.select { |job| job["job_class"] == "Accounting::FetchRecordJob" }.map { |job| job["arguments"].drop(1) }
    assert_equal [ [ "Invoice", "130" ], [ "Payment", "143" ] ], fetched
    assert gateway.accounting_records.find_by(external_id: "131").deleted?
  end

  test "a notification with a bad signature is refused" do
    gateway = create_quickbooks_gateway
    body = qbo_fixture("webhook")

    with_accounting do
      assert_no_enqueued_jobs do
        post webhook_gateway_path(gateway), params: body, headers: { "Content-Type" => "application/json", "intuit-signature" => sign_webhook(body, "wrong") }
      end
    end
    assert_response :bad_request
    assert_not gateway.verify_webhook(body, {})
    assert_not create_quickbooks_gateway(verifier: "").verify_webhook(body, "HTTP_INTUIT_SIGNATURE" => sign_webhook(body, ""))
  end

  # -- Turned off --

  test "while the feature is off the pages refuse and notifications are refused" do
    gateway = create_quickbooks_gateway
    body = qbo_fixture("webhook")
    sign_in @architect

    with_accounting(false) do
      [ connect_accounting_connection_path(gateway), disconnect_accounting_connection_path(gateway),
        accounting_quickbooks_callback_path(code: "x", state: "y"), accounting_connection_records_path(gateway) ].each do |path|
        get path
        assert_redirected_to root_path
        assert_equal "Accounting is turned off", flash[:notice]
      end
      assert_no_enqueued_jobs { post sync_accounting_connection_path(gateway) }
      assert_redirected_to root_path

      post webhook_gateway_path(gateway), params: body, headers: { "Content-Type" => "application/json", "intuit-signature" => sign_webhook(body) }
      assert_response :bad_request
    end
    assert_equal "connected", gateway.reload.connection_status
    assert_empty @fake.requests
  end
end
