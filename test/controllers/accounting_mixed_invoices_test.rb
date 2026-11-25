require "test_helper"
require_relative "../support/accounting_rules_world"

# The warning for invoices a rule counts that also hold items it doesn't
# filter for: on the rule page and its form's preview, for admins only.
class AccountingMixedInvoicesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    add_item("dues", "Membership Dues")
    add_item("travel", "Travel - 2 District Events")
    add_charge("58", "I1", total: 50_000, items: %w[ dues travel ], label: "Invoice 1114 · Membership Dues", number: "1114",
      external_url: "https://qbo.example.com/invoice?txnId=I1")
    add_charge("58", "I2", total: 30_000, items: %w[ dues ], label: "Invoice 1115 · Membership Dues", number: "1115")
    @rule = create_rule(read_permission: "family", amount_permission: "family", filters: { "items" => [ "dues" ] })
    evaluate(@rule)
  end

  def add_item(id, name)
    accounting_source.accounting_records.create!(entity_type: "Item", external_id: id, role: "item", name: name, data: {})
  end

  test "a mixed invoice warns and names the other item" do
    sign_in @laura.user

    with_accounting { get accounting_rule_path(@rule) }

    assert_response :success
    assert_select "#accounting-mixed-invoices", text: /1 invoice counted here also has other items \(Travel - 2 District Events\)\. The whole invoice counts toward this rule, because payments apply to whole invoices\./
    assert_select "#accounting-mixed-invoices tbody tr", count: 1
    assert_select "#accounting-mixed-invoices tbody tr", text: /1114\s+Davolio, Nancy\s+Sep 01\s+Travel - 2 District Events/
    assert_select "#accounting-mixed-invoices a[href=?]", accounting_connection_record_path(accounting_source, @rule.gateway.accounting_records.find_by(external_id: "I1"))
    assert_select "#accounting-mixed-invoices a[href=?]", "https://qbo.example.com/invoice?txnId=I1" if accounting_source.capabilities.include?(:deep_links)
    assert_select "#accounting-mixed-invoices details", count: 0
  end

  test "the list collapses when it is long" do
    6.times { |n| add_charge("58", "M#{n}", total: 10_000, items: %w[ dues travel ], number: "20#{n}") }
    sign_in @laura.user

    with_accounting { get accounting_rule_path(@rule) }

    assert_select "#accounting-mixed-invoices", text: /7 invoices counted here also have other items/
    assert_select "#accounting-mixed-invoices details tbody tr", count: 7
  end

  test "single-purpose invoices don't warn" do
    @rule.gateway.accounting_records.find_by(external_id: "I1").update!(item_ids: %w[ dues ])
    sign_in @laura.user

    with_accounting { get accounting_rule_path(@rule) }

    assert_response :success
    assert_select "#accounting-mixed-invoices", count: 0
  end

  test "a rule with no item filter never warns" do
    open_rule = create_rule("Everything", filters: {})
    evaluate(open_rule)
    sign_in @laura.user

    with_accounting { get accounting_rule_path(open_rule) }

    assert_response :success
    assert_select "#accounting-mixed-invoices", count: 0
  end

  test "voided and unlinked customers' invoices aren't counted" do
    @rule.gateway.accounting_records.find_by(external_id: "I1").update!(voided: true)
    add_charge("99", "I9", total: 10_000, items: %w[ dues travel ])
    sign_in @laura.user

    with_accounting { get accounting_rule_path(@rule) }

    assert_select "#accounting-mixed-invoices", count: 0
  end

  test "the form's preview shows it for the unsaved filter" do
    open_rule = create_rule("Everything", filters: {})
    sign_in @laura.user

    with_accounting do
      patch accounting_rule_path(open_rule), params: { tab: "records", preview: "1", accounting_rule: { filters: { items: [ "dues" ] } } }
    end

    assert_response :success
    assert_select "#accounting-rule-preview #accounting-mixed-invoices", text: /1 invoice counted here also has other items \(Travel - 2 District Events\)/
    assert_equal({}, open_rule.reload.filters)
  end

  test "members and managers see no warning on the rule page, Account tab or statement" do
    evaluate(@rule)
    [ @nancy, @andrew ].each do |viewer|
      sign_in viewer.user

      with_accounting do
        get accounting_rule_path(@rule)
        assert_no_match(/other items/, response.body)
        get person_accounting_path(@nancy)
        assert_no_match(/other items/, response.body)
        get person_accounting_statement_path(@nancy)
        assert_no_match(/other items/, response.body)
      end
    end
  end
end
