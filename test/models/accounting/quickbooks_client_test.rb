require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::QuickbooksClientTest < ActiveSupport::TestCase
  include AccountingWorld

  API = "https://sandbox-quickbooks.api.intuit.com/v3/company/#{AccountingWorld::REALM}".freeze

  setup do
    @gateway = create_quickbooks_gateway
    @fake = fake_quickbooks
    @client = @gateway.client
  end

  teardown { reset_fake_quickbooks }

  # -- What may be sent --

  test "GET to this company's API path is allowed" do
    @fake.on(:get, "/companyinfo/", body: qbo_fixture("company_info"))

    assert_equal "Northwind Robotics Club", @client.company_info["CompanyName"]
    request = @fake.requests.last
    assert_equal "Bearer access-token", request.headers["Authorization"]
    assert_equal Accounting::Quickbooks::MINOR_VERSION, request.query["minorversion"]
  end

  test "token and revoke POSTs are allowed" do
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))
    @fake.on(:post, Accounting::Quickbooks::REVOKE_URL, body: "")

    @client.request(:post, Accounting::Quickbooks::TOKEN_URL, body: "grant_type=refresh_token")
    @client.request(:post, Accounting::Quickbooks::REVOKE_URL, body: "{}")
    assert_equal 2, @fake.requests.size
  end

  test "every other method, host, path or body is refused before anything is sent" do
    refused = [
      [ :post, "#{API}/invoice", { "Line" => [] }.to_json ],
      [ :post, "#{API}/invoice?operation=delete", { "Id" => "130", "SyncToken" => "2" }.to_json ],
      [ :post, "#{API}/invoice?operation=void", { "Id" => "130", "SyncToken" => "2" }.to_json ],
      [ :post, "#{API}/invoice", { "Id" => "130", "SyncToken" => "2", "sparse" => true }.to_json ],
      [ :post, "#{API}/customer?requestid=abc", { "DisplayName" => "New" }.to_json ],
      [ :post, "#{API}/payment", { "TotalAmt" => 10 }.to_json ],
      [ :post, "#{API}/invoice/130/send?sendTo=a@example.com", nil ],
      [ :post, "#{Accounting::Quickbooks::TOKEN_URL}?extra=1", "" ],
      [ :post, "https://evil.example.com/oauth2/v1/tokens/bearer", "" ],
      [ :delete, "#{API}/invoice/130", nil ],
      [ :put, "#{API}/invoice/130", nil ],
      [ :get, "https://quickbooks.api.intuit.com/v3/company/#{AccountingWorld::REALM}/invoice/130", nil ],
      [ :get, "https://sandbox-quickbooks.api.intuit.com/v3/company/4620816365000000/invoice/130", nil ],
      [ :get, "http://sandbox-quickbooks.api.intuit.com/v3/company/#{AccountingWorld::REALM}/invoice/130", nil ],
      [ :get, "https://evil.example.com/v3/company/#{AccountingWorld::REALM}/invoice/130", nil ],
      [ :get, "not a url", nil ]
    ]

    refused.each do |method, url, body|
      assert_raises(Accounting::Quickbooks::Client::NotAllowed, "#{method} #{url}") { @client.request(method, url, body: body) }
    end
    assert_empty @fake.requests
  end

  test "reads need a connected company" do
    @gateway.record_state!(realm_id: nil)

    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.request(:get, "#{API}/invoice/130") }
  end

  test "creating and sending raise while writing is off" do
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.create_invoice({}, request_id: "a") }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.create_customer({}, request_id: "a") }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.send_invoice("130", email: "a@example.com") }
    assert_empty @fake.requests
  end

  # -- Billing's writes --

  test "creating an invoice and a customer is allowed with a requestid while writing is on" do
    @gateway.update!(allow_create_charges: "true")
    @fake.on(:post, "/invoice?", body: qbo_fixture("invoice_created"))
    @fake.on(:post, "/customer?", body: qbo_fixture("customer_created"))

    invoice = @client.create_invoice({ "CustomerRef" => { "value" => "58" }, "Line" => [] }, request_id: "req-1")
    customer = @client.create_customer({ "DisplayName" => "Andrew Fuller" }, request_id: "req-2")

    assert_equal "201", invoice["Id"]
    assert_equal "71", customer["Id"]
    invoice_request, customer_request = @fake.api_requests
    assert_equal "/v3/company/#{AccountingWorld::REALM}/invoice", invoice_request.uri.path
    assert_equal({ "requestid" => "req-1", "minorversion" => Accounting::Quickbooks::MINOR_VERSION }, invoice_request.query)
    assert_equal({ "CustomerRef" => { "value" => "58" }, "Line" => [] }, JSON.parse(invoice_request.body))
    assert_equal "Bearer access-token", invoice_request.headers["Authorization"]
    assert_equal "req-2", customer_request.query["requestid"]
  end

  test "with writing on, a create is still refused without a requestid, with an Id, SyncToken or sparse body, or with an operation" do
    @gateway.update!(allow_create_charges: "true")
    refused = [
      [ "#{API}/invoice?minorversion=75", { "Line" => [] } ],
      [ "#{API}/invoice?requestid=a", { "Id" => "130", "Line" => [] } ],
      [ "#{API}/invoice?requestid=a", { "SyncToken" => "2", "Line" => [] } ],
      [ "#{API}/invoice?requestid=a", { "id" => "130" } ],
      [ "#{API}/invoice?requestid=a", { "sparse" => true } ],
      [ "#{API}/invoice?requestid=a&operation=void", { "Line" => [] } ],
      [ "#{API}/invoice?requestid=a&operation=delete", { "Line" => [] } ],
      [ "#{API}/customer?requestid=a&operation=update", { "DisplayName" => "New" } ],
      [ "#{API}/invoice/130?requestid=a", { "Line" => [] } ],
      [ "#{API}/payment?requestid=a", { "TotalAmt" => 10 } ],
      [ "#{API}/creditmemo?requestid=a", { "TotalAmt" => 10 } ],
      [ "https://sandbox-quickbooks.api.intuit.com/v3/company/4620816365000000/invoice?requestid=a", { "Line" => [] } ]
    ]

    refused.each do |url, body|
      assert_raises(Accounting::Quickbooks::Client::NotAllowed, url) { @client.request(:post, url, body: body.to_json) }
    end
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.request(:post, "#{API}/invoice?requestid=a", body: "not json") }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.create_invoice({ "Line" => [] }, request_id: nil) }
    assert_empty @fake.requests
  end

  test "sending is allowed only for an invoice a billing line of this gateway created" do
    @gateway.update!(allow_create_charges: "true")
    @fake.on(:post, "/send", body: qbo_fixture("invoice_sent"))
    person = create_linkable_person("Andrew", "Fuller")
    run = AccountingBillingRun.create!(gateway: @gateway, created_by: person, item_external_id: "21", amount_cents: 45_000, status: "running")
    run.lines.create!(person: person, customer_external_id: "58", amount_cents: 45_000, status: "created", external_id: "201")
    other = create_quickbooks_gateway
    other_run = AccountingBillingRun.create!(gateway: other, created_by: person, item_external_id: "21", amount_cents: 45_000)
    other_run.lines.create!(person: person, customer_external_id: "58", amount_cents: 45_000, status: "created", external_id: "202")
    run.lines.create!(person: create_linkable_person("Janet", "Leverling"), customer_external_id: "60", amount_cents: 45_000, status: "failed", external_id: "203")

    assert_equal "EmailSent", @client.send_invoice("201", email: "nancy.ward@example.com")["EmailStatus"]
    request = @fake.api_requests.last
    assert_equal "/v3/company/#{AccountingWorld::REALM}/invoice/201/send", request.uri.path
    assert_equal "nancy.ward@example.com", request.query["sendTo"]

    [ "130", "202", "203" ].each do |id|
      assert_raises(Accounting::Quickbooks::Client::NotAllowed, id) { @client.send_invoice(id, email: "nancy.ward@example.com") }
    end
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.request(:post, "#{API}/invoice/201/send?sendTo=a@example.com&operation=void") }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.request(:post, "#{API}/invoice/201/send?sendTo=a@example.com", body: "{}") }
    assert_equal 1, @fake.requests.size
  end

  test "creating and sending raise while writing is off, even for an allowed request" do
    person = create_linkable_person("Andrew", "Fuller")
    run = AccountingBillingRun.create!(gateway: @gateway, created_by: person, item_external_id: "21", amount_cents: 45_000)
    run.lines.create!(person: person, customer_external_id: "58", amount_cents: 45_000, status: "created", external_id: "201")

    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.request(:post, "#{API}/invoice?requestid=a", body: { "Line" => [] }.to_json) }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.request(:post, "#{API}/invoice/201/send?sendTo=a@example.com") }
    assert_empty @fake.requests
  end

  test "a refused create raises with QuickBooks' message; rate limits are temporary" do
    @gateway.update!(allow_create_charges: "true")
    @fake.on(:post, "/customer?", status: 400, body: qbo_fixture("customer_duplicate_name"))
    @fake.on(:post, "/invoice?", status: 429, body: "")

    error = assert_raises(Accounting::Quickbooks::Client::Error) { @client.create_customer({ "DisplayName" => "Ward, Nancy" }, request_id: "a") }
    assert_match "Duplicate Name Exists Error", error.message
    assert_raises(Accounting::TemporaryFailure) { @client.create_invoice({ "Line" => [] }, request_id: "b") }
  end

  # -- Reads --

  test "a query pages past 1000 rows" do
    pages = []
    @fake.on(:get, "/query") do |request|
      statement = request.query["query"]
      pages << statement
      start = statement[/STARTPOSITION (\d+)/, 1].to_i
      count = start == 1 ? 1000 : 3
      { "QueryResponse" => { "Customer" => Array.new(count) { |i| { "Id" => (start + i).to_s } } } }
    end

    ids = []
    @client.query("Customer", where: "Active IN (true, false)") { |row| ids << row["Id"] }

    assert_equal 1003, ids.size
    assert_equal [ "select * from Customer where Active IN (true, false) STARTPOSITION 1 MAXRESULTS 1000",
                   "select * from Customer where Active IN (true, false) STARTPOSITION 1001 MAXRESULTS 1000" ], pages
  end

  test "invoice reads ask for the pay link" do
    @fake.on(:get, "/invoice/130", body: qbo_fixture("invoice_130"))

    assert_equal "4", @client.get("Invoice", "130")["SyncToken"]
    assert_equal "invoiceLink", @fake.requests.last.query["include"]
  end

  test "a record QuickBooks doesn't have reads as nil" do
    @fake.on(:get, "/invoice/131", status: 400, body: qbo_fixture("not_found"))

    assert_nil @client.get("Invoice", "131")
  end

  test "changes yield each type's rows and deletes" do
    @fake.on(:get, "/cdc", body: qbo_fixture("cdc"))
    since = Time.utc(2026, 11, 20, 12)

    changes = []
    @client.changes(%w[ Invoice Payment ], since) { |type, row, deleted| changes << [ type, row["Id"], deleted ] }

    assert_equal [ [ "Invoice", "130", false ], [ "Invoice", "131", true ], [ "Payment", "142", false ] ], changes
    assert_equal "Invoice,Payment", @fake.requests.last.query["entities"]
    assert_equal "2026-11-20T12:00:00Z", @fake.requests.last.query["changedSince"]
  end

  test "rate limits and outages are temporary" do
    @fake.on(:get, "/companyinfo/", status: 429, body: "")
    assert_raises(Accounting::TemporaryFailure) { @client.company_info }

    outage = AccountingWorld::FakeTransport.new.on(:get, "/companyinfo/", status: 503, body: "")
    assert_raises(Accounting::TemporaryFailure) { Accounting::Quickbooks::Client.new(@gateway, transport: outage).company_info }
  end

  test "API calls are counted" do
    @fake.on(:get, "/companyinfo/", body: qbo_fixture("company_info"))

    2.times { @client.company_info }
    assert_equal 2, @gateway.reload.calls_in_month
  end

  # -- Tokens --

  test "connecting saves the tokens" do
    gateway = create_quickbooks_gateway(connected: false)
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))

    freeze_time do
      gateway.client.exchange_code("auth-code", redirect_uri: "http://localhost/accounting/quickbooks/callback")

      credential = gateway.reload.accounting_credential
      assert_equal "new-access-token", credential.access_token
      assert_equal "rotated-refresh-token", credential.refresh_token
      assert_equal 1.hour.from_now, credential.access_token_expires_at
      assert_equal 101.days.from_now, credential.refresh_token_expires_at
    end
    form = @fake.token_requests.last.form
    assert_equal({ "grant_type" => "authorization_code", "code" => "auth-code", "redirect_uri" => "http://localhost/accounting/quickbooks/callback" }, form)
    assert_equal "Basic #{Base64.strict_encode64('client-id:client-secret')}", @fake.token_requests.last.headers["Authorization"]
  end

  test "the authorize URL asks for the accounting scope" do
    url = URI(@client.authorize_url(state: "abc", redirect_uri: "http://localhost/cb"))
    query = Rack::Utils.parse_query(url.query)

    assert_equal "appcenter.intuit.com", url.host
    assert_equal({ "client_id" => "client-id", "response_type" => "code", "scope" => "com.intuit.quickbooks.accounting",
                   "redirect_uri" => "http://localhost/cb", "state" => "abc" }, query)
  end

  test "a token with more than five minutes left is used as it is" do
    @fake.on(:get, "/companyinfo/", body: qbo_fixture("company_info"))

    @client.company_info
    assert_empty @fake.token_requests
  end

  test "a token about to run out is refreshed first, and the rotated refresh token saved" do
    @gateway.accounting_credential.update!(access_token_expires_at: 4.minutes.from_now)
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))
    @fake.on(:get, "/companyinfo/", body: qbo_fixture("company_info"))

    @client.company_info

    assert_equal 1, @fake.token_requests.size
    assert_equal({ "grant_type" => "refresh_token", "refresh_token" => "refresh-token" }, @fake.token_requests.first.form)
    assert_equal "Bearer new-access-token", @fake.api_requests.last.headers["Authorization"]
    credential = @gateway.accounting_credential.reload
    assert_equal "rotated-refresh-token", credential.refresh_token
    assert_operator credential.access_token_expires_at, :>, 50.minutes.from_now
  end

  test "two clients refreshing at once make one call" do
    @gateway.accounting_credential.update!(access_token_expires_at: 1.minute.from_now)
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))
    # A second job loaded the same gateway before the first refreshed.
    other = Gateway.find(@gateway.id)
    other.accounting_credential

    assert_equal "new-access-token", @client.access_token
    assert_equal "new-access-token", other.client.access_token
    assert_equal 1, @fake.token_requests.size
  end

  test "a refused refresh asks for a reconnect and fires sync failed" do
    @gateway.accounting_credential.update!(access_token_expires_at: 1.minute.from_now)
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, status: 400, body: qbo_fixture("token_refused"))
    Hook.create!(name: "Tell the treasurer", event: "accounting - sync failed", code: "model.record_state!(hook_saw: model.connection_status)")

    assert_raises(Accounting::ReconnectNeeded) { @client.access_token }

    @gateway.reload
    assert_equal "needs_reconnect", @gateway.connection_status
    assert_equal "needs_reconnect", @gateway.configuration["hook_saw"]
    assert_match "invalid_grant", @gateway.last_error
    assert_not @gateway.syncable?
  end

  test "a 401 refreshes once and retries; a second 401 asks for a reconnect" do
    accepted = [ "Bearer new-access-token" ]
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, body: qbo_fixture("token"))
    @fake.on(:get, "/companyinfo/") { |request| accepted.include?(request.headers["Authorization"]) ? qbo_fixture("company_info") : [ 401, "" ] }

    assert_equal "Northwind Robotics Club", @client.company_info["CompanyName"]
    assert_equal 1, @fake.token_requests.size

    accepted.clear
    assert_raises(Accounting::ReconnectNeeded) { @client.company_info }
    assert_equal 2, @fake.token_requests.size
    assert_equal "needs_reconnect", @gateway.reload.connection_status
  end

  test "disconnecting revokes the refresh token" do
    @fake.on(:post, Accounting::Quickbooks::REVOKE_URL, body: "")

    assert @client.revoke!
    request = @fake.requests.last
    assert_equal({ "token" => "refresh-token" }, JSON.parse(request.body))
    assert_equal "Basic #{Base64.strict_encode64('client-id:client-secret')}", request.headers["Authorization"]
  end
end
