require "test_helper"
require_relative "../support/accounting_rules_world"

# A person's Account tab and statement: what each viewer sees, and that
# credits never show their reason to anyone but admins.
class AccountingAccountTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @nancy, by: @laura)
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    @janet = create_rule_person("Janet", "Leverling", team: @team)
    @steven = create_rule_person("Steven", "Buchanan")

    add_charge("58", "I1", total: 40_000, balance: 5_000, label: "Invoice 1042 · Dues", items: [ "dues" ], txn_date: Date.new(2026, 9, 1),
      pay_url: "https://pay.example.com/1042", description: "Season dues")
    add_payment("58", "P1", total: 15_000, applied: { "I1" => 10_000 }, unapplied: 5_000, txn_date: Date.new(2026, 9, 10))
    add_payment("58", "CM1", total: 25_000, applied: { "I1" => 25_000 }, role: "credit", public_label: "Credit",
      description: "Hardship scholarship", txn_date: Date.new(2026, 9, 20))
    add_charge("58", "I9", total: 9_900, label: "Invoice 1050 · Trip", items: [ "trip" ], txn_date: Date.new(2026, 10, 1), description: "Trip")
    add_payment("58", "P9", total: 9_900, applied: { "I9" => 9_900 }, txn_date: Date.new(2026, 10, 2))

    @rule = create_rule(read_permission: "family", amount_permission: "family", show_pay_links: true, filters: { "items" => [ "dues" ] },
      milestones: [ { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 },
                    { name: "Paid in full", due_on: Date.new(2099, 1, 15), balance_at_most_cents: 0 } ])
    evaluate(@rule)
  end

  test "the person sees each rule's status, amounts, charges, pay link and unapplied payment" do
    sign_in @nancy.user

    with_accounting { get person_accounting_path(@nancy) }

    assert_response :success
    assert_select "a.nav-link.active", text: "Account"
    result = result_for(@rule, @nancy)
    assert_select "##{dom_id(result)}" do
      assert_select ".badge", text: "Partly paid"
      assert_select "*", text: /Next: \$50\.00 by/
      assert_select "*", text: /Balance remaining \$50\.00 of \$400\.00/
      assert_select "li", text: /Invoice 1042 · Dues: \$50\.00 left of \$400\.00/
      assert_select "*", text: /A payment of \$50\.00 is waiting to be applied/
      assert_select "a[href=?]", "https://pay.example.com/1042", text: "Pay online"
    end
    assert_select "a[href=?]", person_accounting_statement_path(@nancy), text: "Statement"
    assert_no_match "scholarship", response.body.downcase
    assert_no_match "Manage links", response.body
  end

  test "a leader sees the status without amounts, dates or the statement when amounts are the family's only" do
    @rule.update!(read_permission: "family", amount_permission: "self")
    sign_in @andrew.user

    with_accounting { get person_accounting_path(@nancy) }

    assert_response :success
    assert_select ".badge", text: "Partly paid"
    assert_select "*", text: /Next: Paid in full/
    assert_no_match "$50.00", response.body
    assert_no_match "Pay online", response.body
    assert_select "a", text: "Statement", count: 0
    with_accounting { get person_accounting_statement_path(@nancy) }
    assert_redirected_to root_path
  end

  test "a guardian sees a ward's account; a teammate and a stranger see nothing" do
    sign_in @margaret.user
    with_accounting { get person_accounting_path(@nancy) }
    assert_select ".badge", text: "Partly paid"

    [ @janet, @steven ].each do |viewer|
      sign_in viewer.user
      with_accounting do
        get person_accounting_path(@nancy)
        assert_redirected_to root_path
        get person_path(@nancy)
      end
      assert_select "a.nav-link", text: "Account", count: 0
    end
  end

  test "the tab shows on the profile for people who may see a result" do
    sign_in @nancy.user

    with_accounting { get person_path(@nancy) }

    assert_select "a.nav-link[href=?]", person_accounting_path(@nancy), text: "Account"
  end

  test "the statement shows only the rule's charges, what was applied to them and unapplied money, each by its public label" do
    sign_in @margaret.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_response :success
    labels = css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
    assert_equal [ "Credit", "Payment", "Invoice 1042 · Dues" ], labels
    assert_select "tbody tr:first-child td:last-child", text: "$0.00"
    assert_select "##{dom_id(record("P1"))} td", text: "$150.00"
    assert_no_match "Invoice 1050", response.body
    assert_no_match "scholarship", response.body.downcase
    assert_no_match "Description", response.body
  end

  test "admins see every record of the person's customers with descriptions" do
    sign_in @laura.user

    with_accounting do
      get person_accounting_statement_path(@nancy)
      assert_match "Hardship scholarship", response.body
      assert_match "Invoice 1050 · Trip", response.body

      get person_accounting_path(@nancy)
    end
    assert_select "a", text: "Manage links"
  end

  test "a statement shows nothing to someone who may see results but no amounts" do
    @rule.update!(amount_permission: "admin")
    sign_in @nancy.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_redirected_to root_path
  end

  test "a non-admin never sees a custom rule's error" do
    broken = create_rule("Broken", kind: "custom", code: 'raise "secret detail"', read_permission: "self")
    evaluate(broken)
    sign_in @nancy.user

    with_accounting { get person_accounting_path(@nancy) }

    assert_select "##{dom_id(result_for(broken, @nancy))}", count: 0
    assert_no_match "Broken", response.body
    assert_no_match "secret detail", response.body

    sign_in @laura.user
    with_accounting { get person_accounting_path(@nancy) }
    assert_select "##{dom_id(result_for(broken, @nancy))}", text: /Error.*secret detail/m
  end

  private
    def dom_id(record)
      ActionView::RecordIdentifier.dom_id(record)
    end

    def record(external_id)
      accounting_source.accounting_records.find_by!(external_id: external_id)
    end
end
