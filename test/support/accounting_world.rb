require_relative "settings_test_helper"

# Helpers for accounting tests: a QuickBooks gateway, a fake transport that
# answers with the recorded sandbox responses in
# test/fixtures/files/quickbooks/ and records every request, ledger and
# file sources, ledgers, and people.
module AccountingWorld
  include SettingsTestHelper

  REALM = "9130350000000000".freeze
  VERIFIER = "verifier-token".freeze

  # Stands in for Accounting::Quickbooks::Transport. Answers come from
  # handlers tried in the order added; a request no handler answers fails
  # the test.
  class FakeTransport
    Request = Struct.new(:method, :url, :headers, :body) do
      def uri = URI(url)
      def query = Rack::Utils.parse_query(uri.query)
      def form = Rack::Utils.parse_query(body.to_s)
    end

    attr_reader :requests

    def initialize
      @requests = []
      @handlers = []
    end

    # Answers requests whose method matches and whose URL contains the text
    # (or matches the regexp). A block gets the request and returns the
    # body, or [status, body].
    def on(method, match = nil, status: 200, body: nil, tid: nil, &block)
      @handlers << [ method, match, status, body, block, tid ]
      self
    end

    def call(method, url, headers: {}, body: nil)
      request = Request.new(method, url, headers, body)
      @requests << request
      handler = @handlers.find do |want, match, *|
        want == method && (match.nil? || (match.is_a?(Regexp) ? url.match?(match) : url.include?(match)))
      end
      raise "No fake QuickBooks answer for #{method.upcase} #{url}" unless handler

      _, _, status, answer, block, tid = handler
      answer = block.call(request) if block
      status, answer = answer if answer.is_a?(Array) && answer.first.is_a?(Integer)
      answer = answer.to_json unless answer.is_a?(String) || answer.nil?
      Accounting::Quickbooks::Transport::Response.new(status: status, body: answer.to_s, intuit_tid: tid)
    end

    def api_requests
      @requests.select { |request| request.url.include?("/v3/company/") }
    end

    def token_requests
      @requests.select { |request| request.url == Accounting::Quickbooks::TOKEN_URL }
    end
  end

  def with_accounting(enabled = true, &block)
    with_settings(feature_accounting: enabled.to_s, &block)
  end

  # The page wraps its table in a Columns chooser with heading sort and filter,
  # remembered under key.
  def assert_column_chooser(key)
    assert_select "[data-controller~='column-chooser'][data-controller~='table-filter'][data-column-chooser-key-value='#{key}']"
  end

  def qbo_fixture(name)
    file_fixture("quickbooks/#{name}.json").read
  end

  def qbo_json(name)
    JSON.parse(qbo_fixture(name))
  end

  # The first row of a fixture's query response.
  def qbo_row(name, entity_type, index = 0)
    qbo_json(name).dig("QueryResponse", entity_type, index)
  end

  def fake_quickbooks
    @fake_quickbooks ||= FakeTransport.new.tap { |fake| Accounting::Quickbooks::Client.transport = fake }
  end

  def reset_fake_quickbooks
    Accounting::Quickbooks::Client.transport = nil
    @fake_quickbooks = nil
  end

  # Answers each type's query with its fixture.
  def answer_queries(fake = fake_quickbooks, **fixtures)
    defaults = { "Customer" => "customers", "Invoice" => "invoices", "Payment" => "payments", "CreditMemo" => "credit_memos",
                 "SalesReceipt" => "sales_receipts", "RefundReceipt" => "refund_receipts", "Item" => "items", "Class" => "classes" }
    fake.on(:get, "/query") do |request|
      entity = request.query["query"][/from (\w+)/, 1]
      name = fixtures.fetch(entity) { defaults.fetch(entity, nil) }
      name ? qbo_fixture(name) : { "QueryResponse" => {} }
    end
  end

  def create_quickbooks_gateway(connected: true, verifier: VERIFIER, token_expires_at: 1.hour.from_now, **configuration)
    gateway = Gateway::QuickbooksGateway.create!(name: "Club books", client_id: "client-id", client_secret: "client-secret",
      webhook_verifier_token: verifier, **configuration)
    if connected
      gateway.create_accounting_credential!(access_token: "access-token", access_token_expires_at: token_expires_at,
        refresh_token: "refresh-token", refresh_token_expires_at: 90.days.from_now)
      gateway.record_state!(realm_id: REALM, connection_status: "connected")
    end
    gateway
  end

  def create_accounting_user(name, admin: false, architect: false)
    user = User.create!(email: "#{name.downcase}@example.com", password: "Password1!", admin: admin, architect: architect)
    Person.create!(user: user, first_name: name, last_name: "Ledger")
    user
  end

  # A person with a login under the given email (or none).
  def create_linkable_person(first_name, last_name, email: nil, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin) if email
    Person.create!(user: user, first_name: first_name, last_name: last_name)
  end

  # Makes guardian a guardian of ward ("Parent of", minor guardianship).
  def add_guardian(guardian, ward, by:)
    type = RelationshipType.find_or_create_by!(parent_label: "Parent of", child_label: "Child of") do |new_type|
      new_type.permission = :added_by_admin
      new_type.guardianship = :minor
    end
    Relationship.create!(parent: guardian, child: ward, relationship_type: type, created_by: by)
  end

  # A customer record as any source's normalize leaves it.
  def create_customer_record(source, id, name:, email: nil, reference: nil, parent: nil, active: true)
    source.accounting_records.create!(entity_type: "Customer", external_id: id, role: "customer", customer_external_id: id,
      name: name, email: email, reference: reference, parent_external_id: parent, active: active, data: {})
  end

  def create_ledger_source(**configuration)
    Gateway::LedgerSource.create!(name: "Member ledgers", **configuration)
  end

  def create_file_source
    Gateway::FileSource.create!(name: "Dues sheet")
  end

  def create_ledger_team(name)
    Team.create!(name: name, team_type: team_types(:one))
  end

  # A ledger on the team owned by each of owners.
  def create_ledger(name, team:, owners: [])
    ledger = Ledger.create!(name: name, team: team)
    owners.each { |owner| ledger.ledger_ownerships.create!(owner: owner) }
    ledger
  end

  # An entry dated at, carrying tags; at keeps entries in a known order.
  def add_entry(ledger, amount_cents, by:, at: Time.current, tags: [], **attributes)
    entry = ledger.ledger_entries.create!(amount_cents: amount_cents, created_by: by, created_at: at, **attributes)
    tags.each { |tag| entry.ledger_taggings.create!(ledger_tag: tag) }
    entry
  end

  def sign_webhook(body, token = VERIFIER)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", token, body))
  end
end
