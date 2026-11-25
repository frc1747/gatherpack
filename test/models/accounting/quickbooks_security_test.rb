require "test_helper"
require_relative "../../support/accounting_world"
require Rails.root.join("db/migrate/20261125100000_move_quickbooks_realm_into_secrets")
require Rails.root.join("db/versions_migrate/20261125100100_scrub_quickbooks_realm_from_audit_logs")

# What QuickBooks sources keep and log: the company id and name encrypted
# and out of the audit log, no job arguments in the log, and no Detail text
# from QuickBooks' errors.
class Accounting::QuickbooksSecurityTest < ActiveJob::TestCase
  include AccountingWorld

  setup do
    @gateway = create_quickbooks_gateway
    @fake = fake_quickbooks
  end

  teardown { reset_fake_quickbooks }

  def raw(column)
    Gateway.connection.select_value("SELECT #{column} FROM gateways WHERE id = #{Gateway.connection.quote(@gateway.id)}")
  end

  # A version's text column as stored, read back through PaperTrail's serializer.
  def stored(log, column)
    PaperTrail.serializer.load(AuditLog.connection.select_value("SELECT #{column} FROM versions WHERE id = #{AuditLog.connection.quote(log.id)}"))
  end

  def run_migration(klass, direction, connection: ActiveRecord::Base.connection)
    ActiveRecord::Migration.suppress_messages { klass.new.exec_migration(connection, direction) }
  end

  # -- Realm id and company name --

  test "the realm id and company name are encrypted at rest and not in the plain configuration" do
    @gateway.record_state!(company_name: "Northwind Robotics Club")

    assert_equal AccountingWorld::REALM, @gateway.reload.realm_id
    assert_equal "Northwind Robotics Club", @gateway.company_name
    assert_no_match(/#{AccountingWorld::REALM}|Northwind/, raw("secrets"))
    assert_no_match(/#{AccountingWorld::REALM}|Northwind/, raw("configuration::text"))
    assert_equal({}, @gateway.configuration.slice("realm_id", "company_name"))
  end

  test "an edit leaves the realm id and company name out of the audit log" do
    @gateway.record_state!(company_name: "Northwind Robotics Club")

    @gateway.reload.update!(environment: "production", name: "Books")
    @gateway.update!(synced_entities: "Customer")

    logs = AuditLog.where(item_type: "Gateway", item_id: @gateway.id)
    assert logs.any? { |log| log.object_changes.to_s.include?("environment") }, "the edit should be logged"
    logs.each do |log|
      assert_no_match(/#{AccountingWorld::REALM}|Northwind|realm_id|company_name/, "#{log.object} #{log.object_changes}")
    end
    assert_equal AccountingWorld::REALM, @gateway.reload.realm_id
  end

  test "saving the gateway form fields keeps the realm id and company name" do
    @gateway.record_state!(company_name: "Northwind Robotics Club")
    @gateway.reload.update!(client_secret: "new-secret", environment: "production")

    assert_equal AccountingWorld::REALM, @gateway.reload.realm_id
    assert_equal "Northwind Robotics Club", @gateway.company_name
  end

  test "the API path still uses the realm id" do
    assert_includes @gateway.reload.client.send(:api_url, "query", {}), "/v3/company/#{AccountingWorld::REALM}/query?"
  end

  # -- Data migrations --

  test "the migration moves the realm id and company name into secrets, and back" do
    @gateway.update_columns(secrets: @gateway.secrets.except("realm_id", "company_name"))
    Gateway.where(id: @gateway.id).update_all([ "configuration = ?::jsonb", { "realm_id" => "777", "company_name" => "Old Name", "environment" => "production", "connection_status" => "connected" }.to_json ])

    run_migration(MoveQuickbooksRealmIntoSecrets, :up)
    @gateway.reload
    assert_equal "777", @gateway.realm_id
    assert_equal "Old Name", @gateway.company_name
    assert_equal({ "environment" => "production", "connection_status" => "connected" }, @gateway.configuration)
    assert_no_match(/777|Old Name/, raw("secrets"))
    assert @gateway.connected?

    run_migration(MoveQuickbooksRealmIntoSecrets, :down)
    @gateway.reload
    assert_equal({ "realm_id" => "777", "company_name" => "Old Name", "environment" => "production", "connection_status" => "connected" }, @gateway.configuration)
    assert_nil @gateway.secrets["realm_id"]
    assert_equal "client-secret", @gateway.client_secret
  end

  test "the migration leaves other gateways and other secrets alone" do
    other = Gateway::LedgerSource.create!(name: "Ledgers")
    other.update_columns(configuration: { "realm_id" => "keep" })

    run_migration(MoveQuickbooksRealmIntoSecrets, :up)

    assert_equal "keep", other.reload.configuration["realm_id"]
    assert_equal "client-secret", @gateway.reload.client_secret
    assert_equal "verifier-token", @gateway.webhook_verifier_token
  end

  test "the audit log scrub removes the two keys and nothing else" do
    old = { "realm_id" => "777", "company_name" => "Old Name", "environment" => "sandbox" }
    log = AuditLog.create!(item_type: "Gateway", item_id: @gateway.id, event: "update",
      object: PaperTrail.serializer.dump({ "name" => "Books", "configuration" => old.to_json }),
      object_changes: PaperTrail.serializer.dump({ "configuration" => [ old.to_json, old.merge("environment" => "production") ] }))
    unrelated = AuditLog.create!(item_type: "Gateway", item_id: @gateway.id, event: "update",
      object_changes: PaperTrail.serializer.dump({ "name" => [ "A", "B" ] }))
    ledger = AuditLog.create!(item_type: "Ledger", item_id: @gateway.id, event: "update",
      object_changes: PaperTrail.serializer.dump({ "realm_id" => [ nil, "kept" ] }))

    run_migration(ScrubQuickbooksRealmFromAuditLogs, :up, connection: AuditLog.connection)

    assert_equal({ "name" => "Books", "configuration" => { "environment" => "sandbox" }.to_json }, stored(log, "object"))
    assert_equal({ "configuration" => [ { "environment" => "sandbox" }.to_json, { "environment" => "production" } ] }, stored(log, "object_changes"))
    assert_equal({ "name" => [ "A", "B" ] }, stored(unrelated, "object_changes"))
    assert_equal({ "realm_id" => [ nil, "kept" ] }, stored(ledger, "object_changes"))
    assert_nothing_raised { run_migration(ScrubQuickbooksRealmFromAuditLogs, :down, connection: AuditLog.connection) }
  end

  # -- Job arguments --

  def capture_job_log
    io = StringIO.new
    previous = ActiveJob::Base.logger
    ActiveJob::Base.logger = Logger.new(io)
    yield
    io.string
  ensure
    ActiveJob::Base.logger = previous
  end

  test "accounting jobs don't log their arguments" do
    log = capture_job_log do
      Accounting::FetchRecordJob.perform_later(@gateway, "Invoice", "secret-entity-id")
      Accounting::EvaluateRuleJob.perform_later(@gateway, [ "secret-person-id" ])
      ProcessGatewayWebhookJob.perform_later(@gateway, %([{"intuitaccountid":"secret-realm"}]), {})
    end

    assert_match "Enqueued Accounting::FetchRecordJob", log
    assert_match "Enqueued ProcessGatewayWebhookJob", log
    assert_no_match(/secret-/, log)
  end

  test "every accounting job that takes arguments turns argument logging off" do
    Rails.application.eager_load!
    jobs = ApplicationJob.descendants.select { |job| job.name.to_s.start_with?("Accounting::") }

    assert_includes jobs, Accounting::FetchRecordJob
    jobs.each do |job|
      next if job.instance_method(:perform).arity.zero?

      assert_equal false, job.log_arguments, "#{job} logs its arguments"
    end
  end

  # -- Error text --

  test "an error keeps the fault code, short message and intuit_tid, never the Detail" do
    @gateway.update!(allow_create_charges: "true")
    @fake.on(:post, "/customer?", status: 400, body: qbo_fixture("customer_duplicate_name"), tid: "1234-abcd")

    error = assert_raises(Accounting::Quickbooks::Client::Error) { @gateway.client.create_customer({ "DisplayName" => "Ward, Nancy" }, request_id: "a") }

    assert_equal "QuickBooks refused creating the customer (6240 Duplicate Name Exists Error, intuit_tid 1234-abcd)", error.message
    assert_no_match(/already using this name|already exists/, error.message)
    assert_equal "6240", error.code
  end

  test "a temporary failure names the intuit_tid" do
    @fake.on(:get, "/query", status: 503, body: "", tid: "9999-ffff")

    error = assert_raises(Accounting::TemporaryFailure) { @gateway.client.query("Customer").to_a }
    assert_match "(intuit_tid 9999-ffff)", error.message
  end

  test "the sign-in's refusal is kept as Intuit's short error word" do
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, status: 400, body: { "error" => "invalid_grant", "error_description" => "Incorrect or invalid refresh token for Northwind" })
    @gateway.accounting_credential.update!(access_token_expires_at: 1.minute.ago)

    assert_raises(Accounting::ReconnectNeeded) { @gateway.client.access_token }
    assert_match "invalid_grant", @gateway.reload.last_error
    assert_no_match(/Northwind/, @gateway.last_error)
  end
end
