require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::BillingTest < ActiveJob::TestCase
  include AccountingRulesWorld

  # Stands in for a process dying after QuickBooks created the invoice but
  # before the line was saved: not a StandardError, so nothing rescues it.
  class Crash < Exception; end # rubocop:disable Lint/InheritException

  setup do
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    @andrew = create_rule_person("Andrew", "Fuller", team: @team)
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @andrew, by: @laura)
    accounting_source.accounting_records.create!(entity_type: "Item", external_id: "21", role: "item", name: "Dues", active: true, data: {})
    add_charge("60", "I2", total: 45_000, balance: 0, items: [ "21" ], label: "Invoice 1043 · Dues")
    @rule = create_rule(team: @team, filters: { "items" => [ "21" ] })
    evaluate(@rule)
    @invoices = {}
  end

  teardown { reset_fake_quickbooks }

  def accounting_source
    @accounting_source ||= create_quickbooks_gateway(allow_create_charges: "true")
  end

  # -- Preview --

  test "the preview's Not invoiced people are the rule's people with no matching charge" do
    rows = preview(who: "not_invoiced").rows

    assert_equal [ @nancy, @andrew ].sort_by(&:last_name), rows.map(&:person)
    assert_equal "not_invoiced", result_for(@rule, @nancy).value
    assert_equal "paid", result_for(@rule, @janet).value
  end

  test "already billed rows start unticked, naming the charge; rows without a warning start ticked" do
    rows = preview(who: "team", team: @team).rows.index_by(&:person)

    assert_equal "Already billed: Invoice 1043 · Dues", rows[@janet].warning
    assert_not rows[@janet].included
    assert rows[@nancy].included
    assert_nil rows[@nancy].warning
  end

  test "without a rule, already billed means this item since the invoice date" do
    add_charge("58", "I3", total: 45_000, items: [ "22" ], txn_date: Date.new(2026, 9, 1))
    add_charge("58", "I4", total: 45_000, items: [ "21" ], txn_date: Date.new(2026, 8, 1), label: "Invoice 1001 · Dues")
    run = billing_run(rule: nil, txn_date: Date.new(2026, 9, 1))
    rows = Accounting::BillingPreview.new(run, access: Accounting::BillingAccess.new(@laura), who: "team", team: @team).rows.index_by(&:person)

    assert_nil rows[@nancy].warning, "an older charge or another item isn't this billing"
    assert_equal "Already billed: Invoice 1043 · Dues", rows[@janet].warning

    run.txn_date = Date.new(2026, 8, 1)
    rows = Accounting::BillingPreview.new(run, access: Accounting::BillingAccess.new(@laura), who: "team", team: @team).rows.index_by(&:person)
    assert_equal "Already billed: Invoice 1001 · Dues", rows[@nancy].warning
  end

  test "people without a customer start unticked: created with the choice and the capability, else skipped" do
    assert_equal "No customer: will be created", preview(who: "team", team: @team, create_customers: true).rows.find { |row| row.person == @andrew }.warning
    row = preview(who: "team", team: @team).rows.find { |found| found.person == @andrew }
    assert_equal "No customer: will be skipped", row.warning
    assert_not row.included
  end

  test "a person with several customers gets the one with the latest charge" do
    link_customer(@nancy, "61")
    link_customer(@nancy, "62")
    add_charge("61", "I5", total: 100, txn_date: Date.new(2026, 7, 1))
    add_charge("62", "I6", total: 100, txn_date: Date.new(2026, 10, 1))

    row = preview(who: "team", team: @team).rows.find { |found| found.person == @nancy }
    assert_equal %w[ 58 61 62 ], row.customers.map(&:customer_external_id)
    assert_equal "62", row.customer_id
  end

  test "picked people are only those the viewer may bill" do
    stranger = create_rule_person("Steven", "Buchanan")
    with_badges do
      rows = Accounting::BillingPreview.new(billing_run, access: treasurer_access, who: "people", person_ids: [ @nancy.id, stranger.id ]).rows

      assert_equal [ @nancy ], rows.map(&:person)
    end
  end

  # -- Who may bill --

  test "admins bill anyone with any active item; a bill grant bills the rule's people the badge covers, with the rule's items" do
    accounting_source.accounting_records.create!(entity_type: "Item", external_id: "22", role: "item", name: "Travel fee", active: true, data: {})
    admin = Accounting::BillingAccess.new(@laura)
    assert admin.allowed?
    assert_equal %w[ 21 22 ], admin.items(accounting_source).map(&:external_id).sort

    with_badges do
      treasurer = treasurer_access
      assert treasurer.allowed?
      assert_equal [ @andrew, @janet, @nancy ].map(&:id).sort, treasurer.people.ids.sort
      assert_not treasurer.may_bill?(@margaret)
      assert_equal %w[ 21 ], treasurer.items(accounting_source).map(&:external_id)
      assert_not Accounting::BillingAccess.new(treasurer.viewer).allowed?, "only from the rule"
    end
  end

  test "397#5: a bill grant stops counting on a turned-off rule, or when its badge no longer counts" do
    with_badges do
      treasurer = treasurer_access
      @rule.update!(enabled: false)
      assert_not Accounting::BillingAccess.new(treasurer.viewer, @rule.reload).allowed?
      assert_empty Accounting::BillingAccess.new(treasurer.viewer, @rule).people

      @rule.update!(enabled: true)
      assert Accounting::BillingAccess.new(treasurer.viewer, @rule.reload).allowed?
      @rule.badge_grants.first.badge.update_column(:permission, Badge.permissions[:added_by_manager])
      assert_not Accounting::BillingAccess.new(treasurer.viewer, AccountingRule.find(@rule.id)).allowed?
    end
  end

  test "397#5: a grant holder's Retry failed skips lines for people they may no longer bill" do
    with_badges do
      access = treasurer_access
      stranger = create_rule_person("Steven", "Buchanan")
      run = billing_run(created_by: access.viewer)
      nancy = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000, status: "failed", error: "Refused")
      steven = run.lines.create!(person: stranger, customer_external_id: "70", amount_cents: 45_000, status: "failed", error: "Refused")

      run.retry_failed!(access)

      assert nancy.reload.pending?
      assert_equal [ "skipped", "Not retried: no longer someone the person retrying may bill" ], [ steven.reload.status, steven.error ]
    end
  end

  test "a grant without bill, or no grant, can't bill" do
    reader = create_rule_person("Robert", "King")
    badge = create_rule_badge("Mentor")
    @rule.badge_grants.create!(badge: badge, amounts: true)
    BadgeAssignment.create!(badge: badge, person: reader)

    with_settings(feature_badges: "true") do
      assert_not Accounting::BillingAccess.new(reader, @rule).allowed?
      assert_empty Accounting::BillingAccess.new(reader, @rule).people
      assert_not Accounting::BillingAccess.new(@nancy, @rule).allowed?
    end
  end

  # -- The job --

  test "each line gets one invoice, with its own request id, and the run finishes" do
    answer_invoices
    run = billing_run(memo: "2027 season dues", due_on: Date.new(2026, 12, 15))
    nancy = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)
    janet = run.lines.create!(person: @janet, customer_external_id: "60", amount_cents: 30_000)

    perform_job(run)

    creates = invoice_posts
    assert_equal 2, creates.size
    assert_equal [ nancy.request_id, janet.request_id ].sort, creates.map { |request| request.query["requestid"] }.sort
    body = JSON.parse(creates.find { |request| request.query["requestid"] == nancy.request_id }.body)
    assert_equal({ "value" => "58" }, body["CustomerRef"])
    assert_equal 450.0, body.dig("Line", 0, "Amount")
    assert_equal "21", body.dig("Line", 0, "SalesItemLineDetail", "ItemRef", "value")
    assert_equal [ "2026-11-24", "2026-12-15", "2027 season dues" ], [ body["TxnDate"], body["DueDate"], body.dig("CustomerMemo", "value") ]
    assert_equal %w[ created created ], [ nancy.reload.status, janet.reload.status ]
    assert_equal @invoices[nancy.request_id], nancy.external_id
    assert run.reload.finished?
    assert_equal 2, run.details["created"]
  end

  test "the new invoice is fetched back at once" do
    answer_invoices
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    perform_job(run)

    assert_enqueued_with(job: Accounting::FetchRecordJob, args: [ accounting_source, "Invoice", line.reload.external_id ])
  end

  test "a crash between creating the invoice and saving the line doesn't bill twice: the retry sends the same request id" do
    crashed = false
    # QuickBooks creates the invoice; the process dies before the answer is saved.
    fake_quickbooks.on(:post, "/invoice?") do |request|
      answer = invoice_for(request)
      crashed ? answer : (crashed = true) && raise(Crash)
    end
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    assert_raises(Crash) { perform_job(run) }
    assert line.reload.pending?
    assert_nil line.external_id

    perform_job(run)

    assert_equal [ line.request_id ] * 2, invoice_posts.map { |request| request.query["requestid"] }
    assert_equal 1, @invoices.size, "QuickBooks holds one invoice"
    assert line.reload.created?
    assert_equal @invoices[line.request_id], line.external_id
  end

  test "a created line is never sent again" do
    answer_invoices
    run = billing_run
    run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000, status: "created", external_id: "199")
    run.lines.create!(person: @janet, customer_external_id: "60", amount_cents: 45_000)

    2.times { perform_job(run) }

    assert_equal 1, invoice_posts.size
    assert_equal "60", JSON.parse(invoice_posts.first.body).dig("CustomerRef", "value")
  end

  test "a customer is created for someone with none, emailed to their first guardian, and linked as created by billing" do
    answer_invoices
    fake_quickbooks.on(:post, "/customer?", body: qbo_fixture("customer_created"))
    run = billing_run(create_customers: true)
    line = run.lines.create!(person: @andrew, amount_cents: 45_000)

    perform_job(run)

    customer_post = fake_quickbooks.api_requests.find { |request| request.uri.path.end_with?("/customer") }
    body = JSON.parse(customer_post.body)
    assert_equal "margaret.peacock@example.com", body.dig("PrimaryEmailAddr", "Address")
    assert_equal "Andrew Fuller", body["DisplayName"]
    assert_equal line.customer_request_id, customer_post.query["requestid"]
    assert_not_equal line.request_id, customer_post.query["requestid"]
    link = accounting_source.accounting_customer_links.find_by!(person: @andrew)
    assert_equal [ "71", "created", @laura ], [ link.customer_external_id, link.source, link.created_by ]
    assert_equal "71", JSON.parse(invoice_posts.first.body).dig("CustomerRef", "value")
    assert_equal [ "created", "71" ], [ line.reload.status, line.customer_external_id ]
    assert_enqueued_with(job: Accounting::FetchRecordJob, args: [ accounting_source, "Customer", "71" ])
  end

  test "the billing email is the first guardian's with an account, else the person's own" do
    assert_equal "margaret.peacock@example.com", Accounting::BillingRunJob.billing_email(@andrew)
    assert_equal "nancy.davolio@example.com", Accounting::BillingRunJob.billing_email(@nancy)

    no_login = Person.create!(first_name: "Anne", last_name: "Dodsworth")
    travel(1.minute) { add_guardian(no_login, @nancy, by: @laura) }
    travel(2.minutes) { add_guardian(@margaret, @nancy, by: @laura) }
    assert_equal "margaret.peacock@example.com", Accounting::BillingRunJob.billing_email(@nancy)
  end

  test "without creating customers, or where the source can't, someone with no customer is skipped" do
    run = billing_run(create_customers: false)
    line = run.lines.create!(person: @andrew, amount_cents: 45_000)

    perform_job(run)

    assert_equal [ "skipped", "No customer" ], [ line.reload.status, line.error ]
    assert_empty fake_quickbooks.api_requests
    assert run.reload.finished?
  end

  test "invoices are emailed only when the run says so and the source can" do
    answer_invoices
    fake_quickbooks.on(:post, "/send", body: qbo_fixture("invoice_sent"))
    run = billing_run(send_from_source: true)
    line = run.lines.create!(person: @andrew, customer_external_id: "70", amount_cents: 45_000)
    quiet = billing_run
    quiet.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    perform_job(run)
    perform_job(quiet)

    sends = fake_quickbooks.api_requests.select { |request| request.uri.path.end_with?("/send") }
    assert_equal 1, sends.size
    assert_equal "/v3/company/#{AccountingWorld::REALM}/invoice/#{line.reload.external_id}/send", sends.first.uri.path
    assert_equal "margaret.peacock@example.com", sends.first.query["sendTo"]
    assert line.sent_at.present?
  end

  test "a send that fails leaves the invoice created, saying it wasn't emailed" do
    answer_invoices
    fake_quickbooks.on(:post, "/send", status: 400, body: qbo_fixture("not_found"))
    run = billing_run(send_from_source: true)
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    perform_job(run)

    assert line.reload.created?
    assert_nil line.sent_at
    assert_match(/\ACreated, but not emailed: /, line.error)
  end

  test "a refused line fails with the message and fires the failed event; Retry failed sends it again with the same request id" do
    refuse = true
    fake_quickbooks.on(:post, "/invoice?") do |request|
      refuse ? [ 400, qbo_fixture("customer_duplicate_name") ] : invoice_for(request)
    end
    Hook.create!(name: "Tell the treasurer", event: "accounting_billing_lines - failed",
      code: "model.update_column(:error, \"seen: \#{model.error}\")")
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    perform_job(run)

    assert line.reload.failed?
    assert_match(/\Aseen: QuickBooks refused creating the invoice \(Duplicate Name Exists Error/, line.error)
    assert run.reload.finished?

    refuse = false
    run.retry_failed!
    assert_equal [ "pending", nil, "running" ], [ line.reload.status, line.error, run.reload.status ]
    assert_enqueued_with(job: Accounting::BillingRunJob, args: [ run ])
    perform_job(run)

    assert line.reload.created?
    assert_equal [ line.request_id ] * 2, invoice_posts.map { |request| request.query["requestid"] }
  end

  test "rate limits are tried again later with the line still pending; past the last try, the lines fail" do
    fake_quickbooks.on(:post, "/invoice?", status: 429, body: "")
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    with_accounting { Accounting::BillingRunJob.perform_now(run) }

    assert line.reload.pending?
    assert_enqueued_jobs 1, only: Accounting::BillingRunJob
    assert_not run.reload.finished?

    perform_enqueued_jobs(only: Accounting::BillingRunJob) { with_accounting { Accounting::BillingRunJob.perform_later(run) } }
    assert line.reload.failed?
    assert_match "429", line.error
    assert run.reload.finished?
  end

  test "the run's create and finished hooks fire with the run, its counts in details" do
    answer_invoices
    Hook.create!(name: "Started", event: "accounting_billing_runs - create",
      code: "model.gateway.record_state!(started_lines: model.lines.count)")
    Hook.create!(name: "Finished", event: "accounting_billing_runs - finished",
      code: "model.gateway.record_state!(finished_counts: model.details)")
    run = billing_run(lines: [ { person: @nancy, customer_external_id: "58", amount_cents: 45_000 }, { person: @andrew, amount_cents: 45_000 } ])

    perform_job(run)

    configuration = accounting_source.reload.configuration
    assert_equal 2, configuration["started_lines"]
    assert_equal({ "pending" => 0, "created" => 1, "failed" => 0, "skipped" => 1, "exported" => 0 }, configuration["finished_counts"])
  end

  test "397#1: nothing is written while the feature is off, and the pending lines fail so the run doesn't wait for ever" do
    answer_invoices
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    with_accounting(false) { Accounting::BillingRunJob.perform_now(run) }

    assert_equal [ "failed", "Accounting is turned off" ], [ line.reload.status, line.error ]
    assert run.reload.finished?
    assert_empty fake_quickbooks.requests
  end

  test "397#1: writing turned off while a run waits fails its pending lines with the setting's words, and the run finishes" do
    answer_invoices
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)
    done = run.lines.create!(person: @janet, customer_external_id: "60", amount_cents: 45_000, status: "created", external_id: "199")
    accounting_source.update!(allow_create_charges: "false")

    perform_job(AccountingBillingRun.find(run.id))

    assert_equal [ "failed", Accounting::Quickbooks::Client::WRITING_OFF ], [ line.reload.status, line.error ]
    assert done.reload.created?
    assert run.reload.finished?
    assert_empty fake_quickbooks.requests
  end

  test "397#1: a source that raises NotImplementedError fails the line instead of leaving it pending" do
    run = billing_run
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)
    run.gateway.define_singleton_method(:create_charge) { |_line| raise NotImplementedError }

    perform_job(run)

    assert line.reload.failed?
    assert run.reload.finished?
  end

  test "397#2: a customer made before the charge failed stays linked, and the retry bills it without making another" do
    refuse = true
    fake_quickbooks.on(:post, "/customer?", body: qbo_fixture("customer_created"))
    fake_quickbooks.on(:post, "/invoice?") { |request| refuse ? [ 400, qbo_fixture("customer_duplicate_name") ] : invoice_for(request) }
    run = billing_run(create_customers: true)
    line = run.lines.create!(person: @andrew, amount_cents: 45_000)

    perform_job(run)

    assert_equal [ "failed", "71" ], [ line.reload.status, line.customer_external_id ]
    assert_equal "created", accounting_source.accounting_customer_links.find_by!(person: @andrew, customer_external_id: "71").source

    refuse = false
    run.retry_failed!
    perform_job(run)

    customer_posts = fake_quickbooks.api_requests.select { |request| request.uri.path.end_with?("/customer") }
    assert_equal 1, customer_posts.size
    assert_equal [ "created", "71" ], [ line.reload.status, JSON.parse(invoice_posts.last.body).dig("CustomerRef", "value") ]
    assert_enqueued_with(job: Accounting::FetchRecordJob, args: [ accounting_source, "Customer", "71" ])
  end

  test "397#2: a crash while emailing leaves the invoice created, never created or emailed again" do
    answer_invoices
    crashed = false
    fake_quickbooks.on(:post, "/send") { crashed ? qbo_fixture("invoice_sent") : (crashed = true) && raise(Crash) }
    run = billing_run(send_from_source: true)
    line = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    assert_raises(Crash) { perform_job(run) }
    assert line.reload.created?
    assert line.external_id.present?

    perform_job(run)

    assert_equal 1, invoice_posts.size
    assert_equal 1, fake_quickbooks.api_requests.count { |request| request.uri.path.end_with?("/send") }
  end

  test "397#10: creating customers on a source that can't skips people without one" do
    run = billing_run(create_customers: true)
    line = run.lines.create!(person: @andrew, amount_cents: 45_000)
    capabilities = run.gateway.capabilities - [ :create_customers ]
    run.gateway.define_singleton_method(:capabilities) { capabilities }

    perform_job(run)

    assert_equal [ "skipped", "No customer" ], [ line.reload.status, line.error ]
    assert_empty fake_quickbooks.api_requests
  end

  test "a run on ledgers adds an entry, and a ledger in the rule's team for someone without one" do
    ledger_team = create_rule_team("Member ledgers")
    source = create_ledger_source(ledger_team_ids: ledger_team.neat_id)
    dues = LedgerTag.create!(name: "Dues")
    nancy_ledger = create_ledger("Nancy Davolio dues", team: ledger_team, owners: [ @nancy ])
    rule = create_rule("Ledger dues", source: source, team: ledger_team)
    run = AccountingBillingRun.create!(gateway: source, rule: rule, created_by: @laura, item_external_id: dues.id, amount_cents: 45_000,
      create_customers: true, send_from_source: true, status: "running")
    run.lines.create!(person: @nancy, customer_external_id: nancy_ledger.id, amount_cents: 45_000)
    new_line = run.lines.create!(person: @andrew, amount_cents: 30_000)

    perform_job(run)

    assert_equal [ -45_000 ], nancy_ledger.ledger_entries.pluck(:amount_cents)
    andrew_ledger = Ledger.find(new_line.reload.customer_external_id)
    assert_equal [ ledger_team, [ @andrew ] ], [ andrew_ledger.team, andrew_ledger.owners ]
    assert_equal [ -30_000 ], andrew_ledger.ledger_entries.pluck(:amount_cents)
    assert_equal "created", source.accounting_customer_links.find_by!(person: @andrew).source
    assert_nil new_line.sent_at, "ledgers don't email"
    assert run.reload.finished?
  end

  test "Duplicate copies no billing runs" do
    run = billing_run
    run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000)

    copy = @rule.duplicate!

    assert_empty copy.billing_runs
    assert_equal [ run ], @rule.billing_runs.to_a
  end

  test "deleting the rule keeps its runs" do
    run = billing_run

    @rule.destroy!

    assert_nil run.reload.rule
  end

  private
    # A treasurer holding a badge the rule grants bill with. Grants count
    # only while badges are on: call inside with_badges.
    def treasurer_access
      unless @treasurer
        @treasurer = create_rule_person("Robert", "King")
        badge = create_rule_badge("Treasurer")
        @rule.badge_grants.create!(badge: badge, amounts: true, bill: true)
        BadgeAssignment.create!(badge: badge, person: @treasurer)
      end
      Accounting::BillingAccess.new(@treasurer, @rule)
    end

    def with_badges(&block)
      with_settings(feature_badges: "true", &block)
    end

    def billing_run(rule: @rule, lines: [], **attributes)
      run = AccountingBillingRun.new({ gateway: accounting_source, rule: rule, created_by: @laura, item_external_id: "21", amount_cents: 45_000,
        txn_date: Date.new(2026, 11, 24), status: "running" }.merge(attributes))
      lines.each { |line| run.lines.build(line) }
      run.save!
      run
    end

    def preview(who:, team: nil, create_customers: false)
      Accounting::BillingPreview.new(billing_run(create_customers: create_customers), access: Accounting::BillingAccess.new(@laura), who: who, team: team)
    end

    def perform_job(run)
      with_accounting { Accounting::BillingRunJob.perform_now(run) }
    end

    # QuickBooks' invoice creates, answered as QuickBooks does: the same
    # requestid gets the first invoice back.
    def answer_invoices
      fake_quickbooks.on(:post, "/invoice?") { |request| invoice_for(request) }
    end

    def invoice_for(request)
      id = @invoices[request.query["requestid"]] ||= (201 + @invoices.size).to_s
      json = qbo_json("invoice_created")
      json["Invoice"]["Id"] = id
      json
    end

    def invoice_posts
      fake_quickbooks.api_requests.select { |request| request.uri.path.end_with?("/invoice") }
    end
end
