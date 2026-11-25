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
      assert_select ".accounting-milestones li", text: /Next\s+Paid in full\s+by .*: \$50\.00 to go/
      assert_select ".accounting-answer", text: /Balance remaining\s+\$50\.00\s+of \$400\.00 charged/
      assert_select ".progress[aria-label=?][aria-valuenow=?]", "Paid $350.00 of $400.00", "87"
      assert_select ".accounting-invoices tbody tr", text: /Invoice 1042\s+Dues\s+Sep 01\s+\$400\.00\s+\$50\.00/
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
    assert_select ".accounting-milestones li", text: /Next\s+Paid in full/
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

  test "admins and holders of the matching badge see the GatherPack ID with a copy button; nobody else does" do
    accounting_source.update!(match_strategies: "reference name", match_field_path: "Notes")
    badge = Badge.create!(name: "Customer Matcher", short: "Mat", color: "#336699", badge_type: badge_types(:one), permission: :added_by_admin)
    BadgeAssignment.create!(badge: badge, person: @andrew)

    with_settings(feature_accounting: "true", feature_badges: "true", accounting_customer_matching_badge: "Customer Matcher") do
      [ @laura, @andrew ].each do |viewer|
        sign_in viewer.user
        get person_accounting_path(@nancy)
        assert_select "tt", text: @nancy.neat_id
        assert_select "button[data-action=?]", "clipboard#copy"
        assert_select "*", text: /Put this in the customer's Notes in QuickBooks and they link on the next sync/
        sign_out viewer.user
      end

      sign_in @nancy.user
      get person_accounting_path(@nancy)
      assert_response :success
      assert_select "tt", count: 0
      assert_select "button[data-action=?]", "clipboard#copy", count: 0
    end
  end

  test "no GatherPack ID shows when no source matches by reference" do
    sign_in @laura.user

    with_accounting { get person_accounting_path(@nancy) }

    assert_response :success
    assert_select "button[data-action=?]", "clipboard#copy", count: 0
  end

  test "the statement shows only the rule's charges, what was applied to them and unapplied money, each by its public label" do
    sign_in @margaret.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_response :success
    assert_column_chooser "accounting-statement"
    assert_select "td[data-sort-value='15000']", minimum: 1
    labels = css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
    assert_equal [ "Credit", "Payment", "Invoice 1042 · Dues" ], labels
    assert_select "tbody tr:first-child td:last-child", text: "$0.00"
    assert_select "##{dom_id(record("P1"))} td", text: "$150.00"
    assert_no_match "Invoice 1050", response.body
    assert_no_match "scholarship", response.body.downcase
    assert_no_match "Description", response.body
  end

  test "393#1: a statement shows only charges a visible rule reads, not every charge its filters allow" do
    @rule.update!(read_permission: "admin", amount_permission: "admin")
    receipts = create_rule("Receipts", kind: "count", read_permission: "family", amount_permission: "family", filters: { "roles" => [ "receipt" ] })
    paid = create_rule("Paid", kind: "amount", measure: "paid", read_permission: "family", amount_permission: "family")
    evaluate(receipts)
    evaluate(paid)
    sign_in @margaret.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_response :success
    assert_no_match "Invoice 1042", response.body
    assert_no_match "Invoice 1050", response.body
    labels = css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
    assert_equal [ "Payment" ], labels, "only the unapplied money"
    assert_select "##{dom_id(record("P1"))} td", text: "$50.00"
  end

  test "393#1 fix round: a paid amount with items and only payments ticked keeps its charges on the statement" do
    @rule.update!(read_permission: "admin", amount_permission: "admin")
    paid = create_rule("Dues paid", kind: "amount", measure: "paid", read_permission: "family", amount_permission: "family",
      filters: { "items" => [ "dues" ], "roles" => [ "payment" ] })
    evaluate(paid)
    sign_in @margaret.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_response :success
    labels = css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
    assert_equal [ "Credit", "Payment", "Invoice 1042 · Dues" ], labels
    assert_no_match "Invoice 1050", response.body
  end

  test "393#1 fix round 2: a paid amount with items that names only receipts puts no charges on the statement" do
    accounting_source.update!(synced_entities: "Customer Invoice Payment CreditMemo SalesReceipt Item")
    @rule.update!(read_permission: "admin", amount_permission: "admin")
    receipts = create_rule("Dues receipts", kind: "amount", measure: "paid", read_permission: "family", amount_permission: "family",
      filters: { "items" => [ "dues" ], "roles" => [ "receipt" ] })
    evaluate(receipts)
    sign_in @margaret.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_response :success
    assert_no_match "Invoice 1042", response.body
    assert_no_match "Invoice 1050", response.body
    labels = css_select("tbody tr td:nth-child(2)").map { |cell| cell.text.strip }
    assert_equal [ "Payment" ], labels, "only the unapplied money"
    assert_select "##{dom_id(record("P1"))} td", text: "$50.00"
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

  test "393#11: the Account tab shows a custom rule's amount" do
    given = create_rule("Given", kind: "custom", code: '{ value: "given", amount_cents: 5_000 }', read_permission: "self", amount_permission: "self")
    evaluate(given)
    sign_in @nancy.user

    with_accounting { get person_accounting_path(@nancy) }

    assert_select "##{dom_id(result_for(given, @nancy))}", text: /\$50\.00/
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
