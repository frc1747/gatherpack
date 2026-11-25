require "test_helper"
require "csv"
require_relative "../support/accounting_rules_world"

class AccountingBillingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, customer: "62")
    @steven = create_rule_person("Steven", "Buchanan")
    accounting_source.accounting_records.create!(entity_type: "Item", external_id: "21", role: "item", name: "Dues", active: true, data: {})
    accounting_source.accounting_records.create!(entity_type: "Item", external_id: "22", role: "item", name: "Travel fee", active: true, data: {})
    add_charge("60", "I2", total: 45_000, balance: 0, items: [ "21" ], label: "Invoice 1043 · Dues")
    @rule = create_rule(team: @team, filters: { "items" => [ "21" ] })
    evaluate(@rule)
  end

  def accounting_source
    @accounting_source ||= create_quickbooks_gateway(allow_create_charges: "true")
  end

  test "Bill people starts from the rule's people who aren't invoiced, already billed ones unticked" do
    sign_in @laura.user

    with_badges { get accounting_rule_path(@rule) }
    assert_select "a", text: "Bill people"

    with_badges { get new_accounting_rule_billing_run_path(@rule) }
    assert_response :success
    assert_select "input[type=radio][name=who][value=not_invoiced][checked]"
    assert_select "select[name='run[item_external_id]'] option", text: "Dues"

    preview_rule(who: "team")
    assert_response :success
    assert_select "##{dom_id(@nancy, :billing)} input[type=checkbox][checked]"
    assert_select "##{dom_id(@janet, :billing)} input[type=checkbox]:not([checked])"
    assert_select "##{dom_id(@janet, :billing)}", text: /Already billed: Invoice 1043 · Dues/
    assert_select ".screen-inline-confirm", text: /Create 2 invoices in QuickBooks\?/
    assert_select "button", text: "Create invoices"

    preview_rule(who: "not_invoiced")
    assert_select "##{dom_id(@nancy, :billing)}"
    assert_select "##{dom_id(@janet, :billing)}", count: 0
  end

  test "creating keeps each person's amount and customer, leaves out the unticked, and asks first" do
    link_customer(@nancy, "61")
    sign_in @laura.user
    rows = {
      @nancy.id => { include: "1", customer: "61", amount: "225.50" },
      @janet.id => { include: "0", customer: "60" },
      @andrew.id => { include: "1", customer: "62", amount: "" }
    }

    assert_no_difference("AccountingBillingRun.count") { create_rule_run(rows: rows) }
    assert_response :unprocessable_content
    assert_match "Choose &quot;Yes, create them&quot; to create the invoices.", response.body

    assert_enqueued_with(job: Accounting::BillingRunJob) { create_rule_run(rows: rows, confirm: "yes") }
    run = AccountingBillingRun.last
    assert_redirected_to accounting_billing_run_path(run)
    assert_equal [ @rule, @laura, "21", 45_000, "running" ], [ run.rule, run.created_by, run.item_external_id, run.amount_cents, run.status ]
    lines = run.lines.index_by(&:person)
    assert_equal [ @andrew, @nancy ].map(&:id).sort, lines.keys.map(&:id).sort
    assert_equal [ "61", 22_550 ], [ lines[@nancy].customer_external_id, lines[@nancy].amount_cents ]
    assert_equal [ "62", 45_000 ], [ lines[@andrew].customer_external_id, lines[@andrew].amount_cents ]
    assert lines.values.all?(&:pending?)
  end

  test "a row for someone outside the preview, or a customer that isn't theirs, isn't billed as posted" do
    sign_in @laura.user

    create_rule_run(who: "not_invoiced", confirm: "yes", rows: {
      @nancy.id => { include: "1", customer: "60" },
      @janet.id => { include: "1", customer: "60" }
    })

    lines = AccountingBillingRun.last.lines.to_a
    assert_equal [ @nancy ], lines.map(&:person)
    assert_equal "58", lines.first.customer_external_id
  end

  test "bad amounts, no item and no one ticked are refused" do
    sign_in @laura.user

    create_rule_run(run: { item_external_id: "", amount: "lots" }, rows: { @nancy.id => { include: "1" } }, confirm: "yes")
    assert_response :unprocessable_content
    assert_match "Choose what to charge for.", response.body
    assert_match "The amount isn&#39;t an amount above zero.", response.body

    create_rule_run(rows: { @nancy.id => { include: "0" } }, confirm: "yes")
    assert_match "Tick at least one person to bill.", response.body

    create_rule_run(rows: { @nancy.id => { include: "1", amount: "-5" } }, confirm: "yes")
    assert_match "Nancy Davolio: the amount isn&#39;t an amount above zero.", response.body
    assert_equal 0, AccountingBillingRun.count
  end

  test "a bill grant holder bills from the rule only, its people and its items" do
    treasurer = create_rule_person("Robert", "King")
    badge = create_rule_badge("Treasurer")
    @rule.badge_grants.create!(badge: badge, amounts: true, bill: true)
    BadgeAssignment.create!(badge: badge, person: treasurer)
    sign_in treasurer.user

    with_badges { get accounting_rule_path(@rule) }
    assert_select "a", text: "Bill people"
    with_badges { get new_accounting_rule_billing_run_path(@rule) }
    assert_response :success
    assert_select "select[name='run[item_external_id]'] option", text: "Travel fee", count: 0

    with_badges { get new_accounting_billing_run_path(gateway_id: accounting_source.to_param) }
    assert_redirected_to root_path

    create_rule_run(run: { item_external_id: "22", amount: "100" }, rows: { @nancy.id => { include: "1" } }, confirm: "yes")
    assert_match "Choose what to charge for.", response.body

    create_rule_run(who: "people", person_ids: [ @nancy.id, @steven.id ], confirm: "yes",
      rows: { @nancy.id => { include: "1" }, @steven.id => { include: "1" } })
    run = AccountingBillingRun.last
    assert_equal [ @nancy ], run.lines.map(&:person)

    with_badges { get accounting_billing_run_path(run) }
    assert_response :success
    with_badges { get accounting_billing_runs_path }
    assert_redirected_to root_path
  end

  test "people without a bill grant, and other people's runs, are refused" do
    reader = create_rule_person("Robert", "King")
    badge = create_rule_badge("Mentor")
    @rule.badge_grants.create!(badge: badge, amounts: true)
    BadgeAssignment.create!(badge: badge, person: reader)
    run = AccountingBillingRun.create!(gateway: accounting_source, rule: @rule, created_by: @laura, item_external_id: "21", amount_cents: 45_000)
    sign_in reader.user

    with_badges { get accounting_rule_path(@rule) }
    assert_response :success
    assert_select "a", text: "Bill people", count: 0

    with_badges { get new_accounting_rule_billing_run_path(@rule) }
    assert_redirected_to root_path
    assert_no_difference("AccountingBillingRun.count") { create_rule_run(confirm: "yes", rows: { @nancy.id => { include: "1" } }) }
    assert_redirected_to root_path
    [ accounting_billing_run_path(run), export_accounting_billing_run_path(run, format: :csv) ].each do |path|
      with_badges { get path }
      assert_redirected_to root_path
    end
    with_badges { post retry_failed_accounting_billing_run_path(run) }
    assert_redirected_to root_path
  end

  test "397#4: rows from a team preview don't carry into Pick people, and Pick people keeps its own rows" do
    sign_in @laura.user
    team_rows = { @nancy.id => { include: "1", warning: "" }, @andrew.id => { include: "1", warning: "" } }

    preview_rule(who: "people", previous_who: "team", person_q: "Buch", rows: team_rows)
    assert_select "##{dom_id(@steven, :billing)}"
    assert_select "##{dom_id(@nancy, :billing)}", count: 0
    assert_select "##{dom_id(@andrew, :billing)}", count: 0

    preview_rule(who: "people", previous_who: "people", person_ids: [ @nancy.id ], rows: { @nancy.id => { include: "0", warning: "" } })
    assert_select "##{dom_id(@nancy, :billing)} input[type=checkbox]:not([checked])"
  end

  test "397#4: a posted tick stands only beside the warning it was given; a new warning unticks the row" do
    sign_in @laura.user

    preview_rule(who: "team", previous_who: "team", rows: { @nancy.id => { include: "1", warning: "" } })
    assert_select "##{dom_id(@nancy, :billing)} input[type=checkbox][checked]"

    add_charge("58", "I9", total: 45_000, items: [ "21" ], label: "Invoice 1050 · Dues")
    preview_rule(who: "team", previous_who: "team", rows: { @nancy.id => { include: "1", warning: "" } })
    assert_select "##{dom_id(@nancy, :billing)} input[type=checkbox]:not([checked])"
    assert_select "##{dom_id(@nancy, :billing)} input[type=hidden][name=?][value=?]", "rows[#{@nancy.id}][warning]",
      "Already billed: Invoice 1050 · Dues"

    assert_no_difference("AccountingBillingLine.count") do
      create_rule_run(who: "team", previous_who: "team", confirm: "yes", rows: { @nancy.id => { include: "1", warning: "" } })
    end
    assert_match "Tick at least one person to bill.", response.body
  end

  test "397#6: the confirm question's count follows the ticks" do
    sign_in @laura.user

    preview_rule(who: "team")

    assert_select "form#billing-form[data-controller=tick-count][data-tick-count-one-value=invoice][data-tick-count-many-value=invoices]"
    assert_select ".screen-inline-confirm [data-tick-count-target=count]", text: "2"
    assert_select ".screen-inline-confirm [data-tick-count-target=noun]", text: "invoices"
    assert_select "input[type=checkbox][data-tick-count-target=box][data-action='tick-count#update']", count: 3
  end

  test "397#11: the rule page's row is Edit and Bill people, with Evaluate now in More" do
    sign_in @laura.user

    with_badges { get accounting_rule_path(@rule) }

    assert_select ".screen-action-row > a.btn", text: "Edit"
    assert_select ".screen-action-row > a.btn-primary", text: "Bill people"
    assert_select ".screen-action-row .dropdown-menu button", text: "Evaluate now"
    assert_select ".screen-action-row > form button", text: "Evaluate now", count: 0
  end

  test "picked people are found by name and added to the preview" do
    sign_in @laura.user

    preview_rule(who: "people", person_q: "Buch")
    assert_select "##{dom_id(@steven, :billing)}", text: /No customer: will be skipped/
    assert_select "##{dom_id(@nancy, :billing)}", count: 0

    preview_rule(who: "people", person_q: "Davo", person_ids: [ @steven.id ])
    assert_select "##{dom_id(@steven, :billing)}"
    assert_select "##{dom_id(@nancy, :billing)}"
  end

  test "Create a customer is offered only where the source can, and says who gets the bill" do
    sign_in @laura.user
    with_badges { get new_accounting_rule_billing_run_path(@rule) }
    assert_select "label", text: "Create a customer for people who don't have one"
    assert_select "label", text: "Email the invoices from QuickBooks"

    accounting_source.update!(allow_create_charges: "false")
    with_badges { get new_accounting_rule_billing_run_path(@rule) }
    assert_select "label", text: "Create a customer for people who don't have one", count: 0
    assert_select "label", text: "Email the invoices from QuickBooks", count: 0
  end

  test "397#3: a source that can't create charges saves the run finished with its lines exported, and the CSV comes from the run's page" do
    file = create_file_source
    file.accounting_records.create!(entity_type: "item", external_id: "dues", role: "item", name: "Dues", active: true, data: {})
    file.accounting_records.create!(entity_type: "customer", external_id: "nancy davolio", role: "customer", customer_external_id: "nancy davolio",
      name: "Nancy Davolio", data: {})
    link_customer(@nancy, "nancy davolio", source: file)
    Hook.create!(name: "Finished", event: "accounting_billing_runs - finished", code: "model.gateway.record_state!(finished_counts: model.details)")
    sign_in @laura.user

    with_badges { get new_accounting_billing_run_path(gateway_id: file.to_param) }
    assert_select ".card-header", text: /you'll get a CSV/

    with_badges do
      post accounting_billing_runs_path(gateway_id: file.to_param), params: {
        run: { item_external_id: "dues", amount: "450", txn_date: "2027-08-01", due_on: "2027-09-01" }, who: "team", team_id: @team.id,
        rows: { @nancy.id => { include: "1", customer: "nancy davolio" }, @janet.id => { include: "1", warning: "No customer: will be skipped" } }
      }
    end

    run = AccountingBillingRun.last
    assert_redirected_to accounting_billing_run_path(run)
    assert_equal "Saved 1 charge for the CSV. Download it and import it into your accounting program.", flash[:notice]
    assert_equal 1, AccountingBillingRun.count
    assert run.finished?
    assert_equal({ @nancy => "exported", @janet => "skipped" }, run.lines.to_h { |line| [ line.person, line.status ] })
    assert_equal 1, file.reload.configuration.dig("finished_counts", "exported")
    assert_no_enqueued_jobs only: Accounting::BillingRunJob

    with_badges { get accounting_billing_run_path(run) }
    assert_select "a[href=?]", export_accounting_billing_run_path(run, format: :csv), text: "Download CSV"
    with_badges { get export_accounting_billing_run_path(run, format: :csv) }
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body)
    assert_equal Accounting::Files::Template::COLUMNS, rows.first
    assert_equal [ [ "Nancy Davolio", "charge", nil, "2027-08-01", "2027-09-01", "Dues", "450.00", nil, nil, nil ] ], rows.drop(1)
  end

  test "the run page lists lines by status with errors, and Retry failed sets them going again" do
    run = AccountingBillingRun.create!(gateway: accounting_source, rule: @rule, created_by: @laura, item_external_id: "21", amount_cents: 45_000, status: "finished")
    failed = run.lines.create!(person: @nancy, customer_external_id: "58", amount_cents: 45_000, status: "failed", error: "QuickBooks refused creating the invoice")
    run.lines.create!(person: @janet, customer_external_id: "99", amount_cents: 45_000, status: "created", external_id: "201")
    sign_in @laura.user

    with_badges { get accounting_billing_run_path(run) }
    assert_column_chooser "accounting-billing-run"
    assert_select "td[data-sort-value='45000']", minimum: 1
    assert_select "##{dom_id(failed)}", text: /QuickBooks refused creating the invoice/
    # 397#8: customers by name, the id where the source hasn't copied one.
    assert_select "##{dom_id(failed)} td", text: "Davolio, Nancy"
    assert_select "##{dom_id(run.lines.find_by!(person: @janet))} td", text: "99"
    assert_select "h1", text: /Dues billing/

    request_id = failed.request_id
    assert_enqueued_with(job: Accounting::BillingRunJob, args: [ run ]) do
      with_badges { post retry_failed_accounting_billing_run_path(run) }
    end
    assert_redirected_to accounting_billing_run_path(run)
    assert_equal [ "pending", request_id ], [ failed.reload.status, failed.request_id ]
  end

  test "admins find the billing runs from Account Status" do
    run = AccountingBillingRun.create!(gateway: accounting_source, created_by: @laura, item_external_id: "21", amount_cents: 45_000, status: "finished")
    sign_in @laura.user

    with_badges { get accounting_rules_path }
    assert_select "a[href=?]", accounting_billing_runs_path, text: "Billing runs"
    with_badges { get accounting_billing_runs_path }
    assert_column_chooser "accounting-billing-runs"
    assert_select "##{dom_id(run)}", text: /Dues billing/
    with_badges { get new_accounting_billing_run_path }
    assert_select "a[href=?]", new_accounting_billing_run_path(gateway_id: accounting_source.to_param)
  end

  test "the routes refuse while the feature is off" do
    sign_in @laura.user

    with_accounting(false) do
      [ accounting_billing_runs_path, new_accounting_rule_billing_run_path(@rule) ].each do |path|
        get path
        assert_redirected_to root_path
      end
      post accounting_rule_billing_runs_path(@rule), params: { run: { item_external_id: "21", amount: "450" }, confirm: "yes" }
      assert_redirected_to root_path
    end
    assert_equal 0, AccountingBillingRun.count
  end

  private
    def with_badges(&block)
      with_settings(feature_accounting: "true", feature_badges: "true", &block)
    end

    def preview_rule(**params)
      create_rule_run(preview: "1", **params)
    end

    def create_rule_run(run: {}, who: "team", rows: {}, **params)
      with_badges do
        post accounting_rule_billing_runs_path(@rule), params: {
          run: { item_external_id: "21", amount: "450", txn_date: "2026-11-24" }.merge(run), who: who, team_id: @team.id, rows: rows
        }.merge(params)
      end
    end
end
