require "test_helper"
require_relative "../support/accounting_rules_world"

# The card each rule gets on a person's Account tab: the answer, milestones,
# invoices and actions, with and without amounts, and with an invoice due
# date only when the rule has no milestones.
class AccountingAccountCardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  OCTOBER_28 = Date.new(2026, 10, 28)

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    add_charge("58", "I1", total: 30_000, balance: 15_000, label: "Invoice 1114 · Membership Dues", due_on: OCTOBER_28,
      txn_date: Date.new(2026, 9, 1), pay_url: "https://pay.example.com/1114")
  end

  def milestone_rule(**attributes)
    create_rule(read_permission: "family", amount_permission: "family", show_pay_links: true, **attributes,
      milestones: [ { name: "Deposit", due_on: Date.new(2026, 10, 1), balance_at_most_percent: 50 },
                    { name: "Paid in full", due_on: Date.new(2099, 2, 11), balance_at_most_cents: 0 } ])
  end

  def show_account(viewer, rule)
    sign_in viewer.user
    with_accounting { get person_accounting_path(@nancy) }
    assert_response :success
    result_for(rule, @nancy)
  end

  test "the card shows the answer, a progress bar, milestones, invoices and one primary Pay online" do
    rule = milestone_rule(description: "Dues for the season")
    evaluate(rule)

    result = show_account(@nancy, rule)

    assert_select "##{dom_id(result)}.card" do
      assert_select "h2", text: "2027 Membership Dues"
      assert_select ".card-header .badge", text: "Partly paid"
      assert_select ".card-header .text-body-secondary", text: "Dues for the season"
      assert_select ".accounting-answer", text: /Balance remaining\s+\$150\.00\s+of \$300\.00 charged\s+\$150\.00 paid/
      assert_select ".progress[role=progressbar][aria-label=?][aria-valuenow=?]", "Paid $150.00 of $300.00", "50"
      assert_select ".accounting-milestones li", count: 2
      assert_select ".accounting-milestones li", text: /Met\s+Deposit\s+by Oct 01/
      assert_select ".accounting-milestones li", text: /Next\s+Paid in full\s+by Feb 11: \$150\.00 to go/
      assert_select ".accounting-invoices thead th", text: %w[ Invoice What Date Total Left ].join(" "), count: 0
      assert_select ".accounting-invoices thead th", count: 5
      assert_select ".accounting-invoices tbody tr", text: /Invoice 1114\s+Membership Dues\s+Sep 01\s+\$300\.00\s+\$150\.00/
      assert_select ".card-body .small", text: /Updated \d{1,2} \w{3}, \d{1,2}:\d{2} [ap]m/
      assert_select ".card-footer a.btn-primary[href=?]", "https://pay.example.com/1114", text: "Pay online"
      assert_select ".card-footer a.btn", text: "Statement"
    end
    assert_no_match(/\s,/, response.body.gsub(/<[^>]*>/, " ").gsub(/\s+/, " ").scan(/Invoice 1114[^<]*/).join, "no stray space before a comma")
  end

  test "a rule with milestones doesn't show an invoice's own due date" do
    rule = milestone_rule
    evaluate(rule)

    show_account(@nancy, rule)

    assert_select ".accounting-invoices thead th", text: "Due", count: 0
    assert_no_match "Oct 28", response.body
    assert_no_match(/due Oct/i, response.body)
  end

  test "a person's own plan also leaves invoice due dates out" do
    rule = milestone_rule
    rule.person_milestones.create!(person: @nancy, name: "First payment", due_on: Date.new(2099, 3, 1), balance_at_most_cents: 0,
      created_by: @laura)
    evaluate(rule)

    show_account(@nancy, rule)

    assert_select ".accounting-milestones li", text: /First payment/
    assert_select ".accounting-invoices thead th", text: "Due", count: 0
    assert_no_match "Oct 28", response.body
  end

  test "a rule without milestones shows each invoice's due date and the next payment line" do
    rule = create_rule(read_permission: "family", amount_permission: "family")
    add_charge("58", "I2", total: 10_000, label: "Invoice 1120 · Trip", due_on: Date.new(2099, 5, 1))
    evaluate(rule)

    result = show_account(@nancy, rule)

    assert_select "##{dom_id(result)}" do
      assert_select ".accounting-milestones", count: 0
      assert_select ".accounting-invoices thead th", text: "Due", count: 1
      assert_select ".accounting-invoices tbody tr", text: /Invoice 1114.*Oct 28/
      assert_select ".accounting-invoices tbody tr", text: /Invoice 1120.*May 01/
      assert_select ".accounting-answer", text: /Overdue: Invoice 1114 · Membership Dues in full · \$150\.00 to meet/
    end
  end

  test "a missed milestone says so, with what it takes to catch up" do
    rule = milestone_rule
    rule.milestones.first.update!(balance_at_most_percent: 10)
    evaluate(rule)

    show_account(@nancy, rule)

    assert_select ".accounting-milestones li", text: /Missed\s+Deposit\s+was due Oct 01: \$120\.00 to go/
    assert_select ".accounting-milestones li", text: /Next\s+Paid in full\s+by Feb 11: \$150\.00 to go/
  end

  test "milestones after the next one are coming up, without a catch-up amount" do
    rule = milestone_rule
    rule.milestones.create!(name: "Final check", due_on: Date.new(2099, 6, 1), balance_at_most_cents: 0)
    evaluate(rule)

    show_account(@nancy, rule)

    assert_select ".accounting-milestones li", text: /Coming up\s+Final check\s+by Jun 01\z/
  end

  test "without amounts the card shows the status and milestones but no money" do
    rule = milestone_rule(amount_permission: "self")
    evaluate(rule)

    result = show_account(@andrew, rule)

    assert_select "##{dom_id(result)}" do
      assert_select ".card-header .badge", text: "Partly paid"
      assert_select ".accounting-milestones li", text: /Met\s+Deposit/
      assert_select ".accounting-milestones li", text: /Next\s+Paid in full/
      assert_select ".accounting-answer", count: 0
      assert_select ".progress", count: 0
      assert_select ".accounting-invoices", count: 0
      assert_select ".card-footer a", count: 0
    end
    assert_no_match "$", response.body
    assert_no_match "Pay online", response.body
  end

  test "a payment waiting to be applied has its own line" do
    rule = milestone_rule
    add_payment("58", "P1", total: 5_000, unapplied: 5_000)
    evaluate(rule)

    show_account(@nancy, rule)

    assert_select ".alert", text: /A payment of \$50\.00 is waiting to be applied\./
  end

  test "several payable invoices each get a Pay online in the table, none in the footer" do
    rule = milestone_rule
    add_charge("58", "I2", total: 10_000, label: "Invoice 1120 · Trip", pay_url: "https://pay.example.com/1120")
    evaluate(rule)

    show_account(@nancy, rule)

    assert_select ".accounting-invoices a[href]", count: 2, text: "Pay online"
    assert_select ".card-footer a", text: "Pay online", count: 0
  end

  test "an admin sees Payment plan and the card's rule link" do
    rule = milestone_rule
    evaluate(rule)

    result = show_account(@laura, rule)

    assert_select "##{dom_id(result)}" do
      assert_select "h2 a[href=?]", accounting_rule_path(rule)
      assert_select ".card-footer a[href=?]", edit_accounting_rule_payment_plan_path(rule, @nancy), text: "Payment plan"
    end
  end

  test "the statement leads with the current balance and has a Print action" do
    rule = milestone_rule
    evaluate(rule)
    sign_in @nancy.user

    with_accounting { get person_accounting_statement_path(@nancy) }

    assert_response :success
    assert_select ".card-body", text: /Current balance\s+\$300\.00/
    assert_select ".card-footer button", text: "Print"
    assert_no_match "Oct 28", response.body
  end
end
