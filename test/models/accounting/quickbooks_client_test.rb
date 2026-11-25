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

  test "creating and sending raise" do
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.create_invoice({}, request_id: "a") }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.create_customer({}, request_id: "a") }
    assert_raises(Accounting::Quickbooks::Client::NotAllowed) { @client.send_invoice("130", email: "a@example.com") }
    assert_empty @fake.requests
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
