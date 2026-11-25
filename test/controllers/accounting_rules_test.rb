require "test_helper"
require_relative "../support/accounting_rules_world"

class AccountingRulesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    @steven = create_rule_person("Steven", "Buchanan")
    add_charge("58", "I1", total: 40_000, balance: 10_000, label: "Invoice 1042 · Dues")
    add_payment("58", "CM1", total: 30_000, applied: { "I1" => 30_000 }, role: "credit", public_label: "Credit",
      description: "Hardship scholarship")
    add_charge("60", "I2", total: 40_000, balance: 0, label: "Invoice 1043 · Dues")
    @rule = create_rule(read_permission: "family", amount_permission: "self", team: @team)
    evaluate(@rule)
  end

  test "routes refuse while the feature is off, and the nav item and tab don't render" do
    sign_in @laura.user

    with_accounting(false) do
      [ accounting_rules_path, accounting_rule_path(@rule), new_accounting_rule_path, person_accounting_path(@nancy),
        person_accounting_statement_path(@nancy) ].each do |path|
        get path
        assert_redirected_to root_path
        assert_equal "Accounting is turned off", flash[:notice]
      end
      post evaluate_accounting_rule_path(@rule)
      assert_redirected_to root_path

      get person_path(@nancy)
      assert_select "a.nav-link", text: "Account", count: 0
      assert_select ".sidebar a[href=?]", accounting_rules_path, count: 0
    end
  end

  test "admins see every rule with counts and totals, and each source's customers and records" do
    sign_in @laura.user

    with_accounting { get accounting_rules_path }

    assert_response :success
    assert_select ".sidebar a[href=?]", accounting_rules_path, text: /Account Status/
    assert_select "##{dom_id(@rule)}", text: /Paid 1 · Partly paid 1/
    assert_select "##{dom_id(@rule)}", text: /Balance remaining \$100\.00/
    assert_select "##{dom_id(accounting_source)} a[href=?]", accounting_connection_customers_path(accounting_source), text: "Customers"
    assert_select "##{dom_id(accounting_source)} a[href=?]", accounting_connection_records_path(accounting_source), text: "Records"
    assert_select "a", text: "New rule"
  end

  test "the records and customers pages sit under Account Status" do
    sign_in @laura.user

    with_accounting { get accounting_connection_customers_path(accounting_source) }
    assert_select ".breadcrumb a[href=?]", accounting_rules_path, text: "Account Status"
    with_accounting { get accounting_connection_records_path(accounting_source) }
    assert_select ".breadcrumb a[href=?]", accounting_rules_path, text: "Account Status"
  end

  test "members see the rules and people the rule lets them, with only their own amounts" do
    sign_in @nancy.user

    with_accounting { get accounting_rules_path }
    assert_select "##{dom_id(@rule)}", text: /Partly paid 1/
    assert_select "##{dom_id(@rule)}", text: /Paid 1/, count: 0
    assert_select "a", text: "New rule", count: 0

    with_accounting { get accounting_rule_path(@rule) }
    assert_response :success
    assert_select "##{dom_id(@nancy)}", text: /Partly paid.*\$100\.00/m
    assert_select "##{dom_id(@janet)}", count: 0
    assert_select "a", text: "Edit", count: 0
  end

  test "the list refuses people who see no rule's results" do
    sign_in @steven.user

    with_accounting { get accounting_rules_path }
    assert_redirected_to root_path
    with_accounting { get accounting_rule_path(@rule) }
    assert_redirected_to root_path
  end

  test "the rule page filters by value, and its CSV carries public labels only" do
    @rule.update!(read_permission: "team", amount_permission: "team")
    sign_in @janet.user

    with_accounting { get accounting_rule_path(@rule, status: "paid") }
    assert_select "##{dom_id(@janet)}"
    assert_select "##{dom_id(@nancy)}", count: 0

    with_accounting { get export_accounting_rule_path(@rule, format: :csv) }
    assert_response :success
    rows = CSV.parse(response.body)
    assert_equal [ "Last name", "First name", "Team", "Status", "Amount", "Charges", "Changed on" ], rows.first
    assert_equal [ "Davolio", "Nancy", "Robotics", "Partly paid", "$100.00", "Invoice 1042 · Dues" ], rows.find { |row| row.first == "Davolio" }.first(6)
    assert_no_match "scholarship", response.body.downcase
  end

  test "the CSV leaves amounts out for people whose amounts the viewer may not see" do
    sign_in @janet.user
    @rule.update!(read_permission: "team")

    with_accounting { get export_accounting_rule_path(@rule, format: :csv) }

    nancy = CSV.parse(response.body).find { |row| row.first == "Davolio" }
    assert_equal [ "Partly paid", nil, nil ], nancy.values_at(3, 4, 5)
  end

  test "admins create a rule and it's evaluated" do
    sign_in @laura.user

    assert_enqueued_with(job: Accounting::EvaluateRuleJob) do
      with_accounting do
        post accounting_rules_path, params: { accounting_rule: { name: "Travel fee 2027", gateway_id: accounting_source.id, kind: "balance" } }
      end
    end

    rule = AccountingRule.find_by!(name: "Travel fee 2027")
    assert_redirected_to edit_accounting_rule_path(rule, tab: "records")
    assert_equal [ "travel_fee_2027", "admin", "admin" ], [ rule.key, rule.read_permission, rule.amount_permission ]
  end

  test "admins who aren't architects can't set code or make a rule custom" do
    sign_in @laura.user

    with_accounting do
      post accounting_rules_path, params: { accounting_rule: { name: "Sneaky", gateway_id: accounting_source.id, kind: "custom", code: "1" } }
    end
    assert_response :unprocessable_content
    assert_not AccountingRule.exists?(name: "Sneaky")

    custom = create_rule("Given", kind: "custom", code: '"none"')
    with_accounting { patch accounting_rule_path(custom), params: { tab: "question", accounting_rule: { code: 'User.delete_all; "x"' } } }
    assert_equal '"none"', custom.reload.code
  end

  test "architect admins write custom rules' code" do
    @laura.user.update!(architect: true)
    sign_in @laura.user

    with_accounting do
      post accounting_rules_path, params: { accounting_rule: { name: "Given", gateway_id: accounting_source.id, kind: "custom", code: '"none"' } }
    end

    assert_equal '"none"', AccountingRule.find_by!(name: "Given").code
  end

  test "editing a rule saves its milestones, filters, labels, levels and badge grants" do
    badge = create_rule_badge("Treasurer")
    sign_in @laura.user

    with_accounting do
      patch accounting_rule_path(@rule), params: { tab: "question", accounting_rule: {
        grace_days: "3", labels: { partial: "Deposit paid" },
        milestones_attributes: { "0" => { name: "Deposit", due_on: "2026-10-01", balance_at_most: "200" }, "1" => { name: "", due_on: "" } }
      } }
      assert_redirected_to edit_accounting_rule_path(@rule, tab: "question")
      patch accounting_rule_path(@rule), params: { tab: "records", accounting_rule: { filters: { items: [ "", "dues" ], txn_date_from: "2026-07-01", min_total: "25.50" } } }
      patch accounting_rule_path(@rule), params: { tab: "people", accounting_rule: { read_permission: "team", amount_permission: "family",
        badge_grants_attributes: { "0" => { badge_id: badge.id, amounts: "1" } } } }
    end

    @rule.reload
    assert_equal [ [ "Deposit", Date.new(2026, 10, 1), 20_000 ] ], @rule.milestones.map { |m| [ m.name, m.due_on, m.balance_at_most_cents ] }
    assert_equal [ 3, "Deposit paid" ], [ @rule.grace_days, @rule.label_for("partial") ]
    assert_equal({ "items" => [ "dues" ], "txn_date_from" => "2026-07-01", "min_total" => 2_550 }, @rule.filters)
    assert_equal [ "team", "family" ], [ @rule.read_permission, @rule.amount_permission ]
    assert_equal [ [ badge, true ] ], @rule.badge_grants.map { |grant| [ grant.badge, grant.amounts ] }
  end

  test "393#10: an amount to skip that isn't one is refused, not cleared" do
    @rule.update!(filters: { "min_total" => 2_500 })
    sign_in @laura.user

    with_accounting do
      patch accounting_rule_path(@rule), params: { tab: "records", accounting_rule: { filters: { min_total: "abc" } } }
      assert_response :unprocessable_content
      assert_match "Skip records under isn&#39;t an amount", response.body

      patch accounting_rule_path(@rule), params: { tab: "records", accounting_rule: { filters: { min_total: "-50" } } }
      assert_response :unprocessable_content
    end
    assert_equal 2_500, @rule.reload.filters["min_total"]
  end

  test "Preview works out the unsaved rule for a few people without saving it" do
    sign_in @laura.user

    with_accounting do
      patch accounting_rule_path(@rule), params: { tab: "records", preview: "1", accounting_rule: { filters: { items: [ "travel" ] } } }
    end

    assert_response :success
    assert_select "#accounting-rule-preview ##{dom_id(@nancy)}", text: /Not invoiced/
    assert_equal({}, @rule.reload.filters)
  end

  test "Preview shows people linked to a customer before the team's other members" do
    %w[ Anne Bea Cleo Dora Edna Fay ].each { |first| create_rule_person(first, "Aaronson", team: @team) }
    sign_in @laura.user

    with_accounting { patch accounting_rule_path(@rule), params: { tab: "records", preview: "1", accounting_rule: { filters: { items: [ "" ] } } } }

    assert_select "#accounting-rule-preview tbody tr", count: 5
    assert_select "#accounting-rule-preview ##{dom_id(@nancy)}", text: /Partly paid/
    assert_select "#accounting-rule-preview ##{dom_id(@janet)}", text: /Paid/
  end

  test "a non-admin never sees a custom rule's errors on its page or in its CSV" do
    broken = create_rule("Broken", kind: "custom", read_permission: "team", amount_permission: "team",
      code: 'person.first_name == "Nancy" ? raise("secret detail") : "fine"')
    evaluate(broken)
    sign_in @janet.user

    with_accounting { get accounting_rule_path(broken) }
    assert_select "##{dom_id(@janet)}"
    assert_select "##{dom_id(@nancy)}", count: 0
    assert_no_match "Error", response.body

    with_accounting { get export_accounting_rule_path(broken, format: :csv) }
    assert_equal [ "Leverling" ], CSV.parse(response.body).drop(1).map(&:first)

    all_broken = create_rule("All broken", kind: "custom", read_permission: "team", code: 'raise "no"')
    evaluate(all_broken)
    assert_not_includes Accounting::Access.visible_rules(@janet.user), all_broken
    assert_includes Accounting::Access.visible_rules(@laura.user), all_broken
  end

  test "a turned-off rule isn't worked out on save or Evaluate now" do
    @rule.update!(enabled: false)
    sign_in @laura.user

    with_accounting do
      assert_no_enqueued_jobs(only: Accounting::EvaluateRuleJob) do
        patch accounting_rule_path(@rule), params: { tab: "question", accounting_rule: { grace_days: "5" } }
        post evaluate_accounting_rule_path(@rule)
      end
      get accounting_rule_path(@rule)
    end
    assert_select "form[action=?]", evaluate_accounting_rule_path(@rule), count: 0

    with_accounting do
      assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ @rule ]) do
        patch accounting_rule_path(@rule), params: { tab: "enabled", accounting_rule: { enabled: "true" } }
      end
    end
  end

  test "the badge grants don't offer billing until it exists" do
    sign_in @laura.user
    with_settings(feature_accounting: "true", feature_badges: "true") { get edit_accounting_rule_path(@rule, tab: "people") }

    assert_select "th", text: "Amounts too"
    assert_no_match "May bill", response.body
  end

  test "393#8: QuickBooks classes are Categories and departments Locations, even with the same ids" do
    accounting_source.accounting_records.create!(entity_type: "Class", external_id: "1", role: "category", name: "Robotics", data: {})
    accounting_source.accounting_records.create!(entity_type: "Department", external_id: "1", role: "category", name: "East Campus", data: {})
    add_charge("58", "I3", total: 1_000, class_ids: [ "1" ], location_ids: [ "1" ])
    sign_in @laura.user

    with_accounting { get edit_accounting_rule_path(@rule, tab: "records") }

    assert_select "fieldset", text: /Categories/ do
      assert_select "label", text: "Robotics"
      assert_select "label", text: "East Campus", count: 0
    end
    assert_select "fieldset", text: /Locations/ do
      assert_select "label", text: "East Campus"
      assert_select "label", text: "Robotics", count: 0
    end
  end

  test "393#11: count and custom rules' totals give a figure before the people they cover, or say nothing" do
    count = create_rule("Records", kind: "count", read_permission: "team", amount_permission: "self", team: @team)
    given = create_rule("Given", kind: "custom", code: '{ value: "given", amount_cents: 5_000 }', read_permission: "team", amount_permission: "self", team: @team)
    plain = create_rule("Plain", kind: "custom", code: '"yes"', read_permission: "team", amount_permission: "self", team: @team)
    [ count, given, plain ].each { |rule| evaluate(rule) }
    sign_in @nancy.user

    with_accounting do
      get accounting_rule_path(count)
      assert_select ".accounting-totals", text: /\A\s*Total 2\s*\(of 1 person\)\s*\z/
      get accounting_rule_path(given)
      assert_select ".accounting-totals", text: /\A\s*Total \$50\.00\s*\(of 1 person\)\s*\z/
      get accounting_rule_path(plain)
      assert_select ".accounting-totals", count: 0
      assert_no_match "(of 1 person)", response.body
    end
  end

  test "the milestones warn when nobody can ever be overdue" do
    original = Gateway::QuickbooksGateway.instance_method(:capabilities)
    Gateway::QuickbooksGateway.define_method(:capabilities) { Set.new }
    sign_in @laura.user

    with_accounting { get edit_accounting_rule_path(@rule, tab: "question") }

    assert_match "Nobody will ever be Overdue: this source has no due dates. Add a milestone.", response.body
  ensure
    Gateway::QuickbooksGateway.define_method(:capabilities, original)
  end

  test "Evaluate now queues the rule; Duplicate opens the copy's edit page" do
    sign_in @laura.user

    assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ @rule ]) do
      with_accounting { post evaluate_accounting_rule_path(@rule) }
    end
    assert_redirected_to accounting_rule_path(@rule)

    with_accounting { post duplicate_accounting_rule_path(@rule) }
    copy = AccountingRule.find_by!(name: "2028 Membership Dues")
    assert_redirected_to edit_accounting_rule_path(copy, tab: "question")
    assert_not copy.enabled?
    assert_empty copy.results
  end

  test "members can't change rules" do
    sign_in @nancy.user

    with_accounting do
      patch accounting_rule_path(@rule), params: { accounting_rule: { read_permission: "everyone" } }
      delete accounting_rule_path(@rule)
      post duplicate_accounting_rule_path(@rule)
    end

    assert_equal "family", @rule.reload.read_permission
    assert_equal 1, AccountingRule.count
  end

  private
    def dom_id(record)
      ActionView::RecordIdentifier.dom_id(record)
    end
end
