require "test_helper"
require_relative "../support/accounting_rules_world"

# Payment plans on the screens: who sees a plan's milestones, that only
# admins see who is on one and its note, and the admin's Payment plan page.
class AccountingPaymentPlansTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", team: @team, customer: "60")
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @nancy, by: @laura)
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    add_charge("58", "I1", total: 40_000, balance: 30_000)
    add_charge("60", "I2", total: 40_000, balance: 30_000)
    @rule = create_rule(read_permission: "family", amount_permission: "family", team: @team,
      milestones: [ { name: "Deposit", due_on: Date.new(2099, 10, 1), balance_at_most_percent: 50 } ])
    @rule.person_milestones.create!(person: @nancy, name: "First payment", due_on: Date.new(2099, 9, 1), balance_at_most_cents: 25_000,
      note: "Agreed with the family by phone", created_by: @laura)
    @rule.person_milestones.create!(person: @nancy, name: "Last payment", due_on: Date.new(2099, 12, 1), balance_at_most_cents: 0, position: 1)
    evaluate(@rule)
  end

  test "the person and their guardian see the plan's milestones, without being told it's a plan" do
    [ @nancy, @margaret ].each do |viewer|
      sign_in viewer.user
      with_accounting { get person_accounting_path(@nancy) }

      assert_response :success
      assert_select ".accounting-plan-milestones li", text: /First payment, by .*, owing at most \$250\.00, \$50\.00 to go/
      assert_select ".accounting-plan-milestones li", text: /Last payment/
      assert_select "*", text: /Next: \$50\.00 by/
      assert_no_match "On a plan", response.body
      assert_no_match "Agreed with the family", response.body
      assert_select "a", text: "Payment plan", count: 0
      sign_out viewer.user
    end
  end

  test "on a rule with a plan, a leader sees only the status for everyone, on the Account tab and the rule page" do
    sign_in @andrew.user

    with_accounting { get person_accounting_path(@nancy) }
    assert_select "##{dom_id(result_for(@rule, @nancy))}", text: /On schedule/
    assert_no_match "First payment", response.body
    assert_no_match "$250.00", response.body
    assert_select ".accounting-plan-milestones", count: 0

    with_accounting { get accounting_rule_path(@rule) }
    assert_response :success
    assert_select "td", text: "On schedule", count: 2, message: "Janet, on the rule's milestones, reads the same as Nancy on her plan"
    assert_no_match "Next:", response.body
    assert_no_match "Deposit", response.body
    assert_no_match "First payment", response.body
    assert_no_match "On a plan", response.body

    with_accounting { get accounting_rule_path(@rule, plan: "1") }
    assert_select "td", text: /Janet/
  end

  test "a leader sees only Overdue for an overdue person on a rule with a plan" do
    add_charge("60", "I3", total: 10_000, balance: 10_000, due_on: Date.new(2020, 1, 1))
    @rule.milestones.create!(name: "Early fee", due_on: Date.new(2020, 1, 1), balance_at_most_cents: 0)
    evaluate(@rule)
    sign_in @andrew.user

    with_accounting { get accounting_rule_path(@rule) }

    assert_equal "overdue", result_for(@rule, @janet).value
    assert_select "td", text: "Overdue", count: 2, message: "the status and the Next column"
    assert_no_match "Early fee", response.body
  end

  test "on a rule without plans, a leader sees the milestone names" do
    @rule.person_milestones.destroy_all
    evaluate(@rule)
    sign_in @andrew.user

    with_accounting { get accounting_rule_path(@rule) }
    assert_select "td", text: /Next: \$100\.00 by/, count: 2
    assert_no_match "On schedule", response.body

    with_accounting { get person_accounting_path(@nancy) }
    assert_select "##{dom_id(result_for(@rule, @nancy))}", text: /Next: \$100\.00 by/
  end

  test "the plan page says who sees the plan by the rule's levels" do
    sign_in @laura.user

    with_accounting { get edit_accounting_rule_payment_plan_path(@rule, @nancy) }
    assert_select ".card-header .text-muted", text: /The person and their guardians see the plan's names and dates and amounts\./

    @rule.update!(read_permission: "family", amount_permission: "self")
    with_accounting { get edit_accounting_rule_payment_plan_path(@rule, @nancy) }
    assert_select ".card-header .text-muted", text: /The person and their guardians see the plan's names and dates, and the person its amounts too\./

    @rule.update!(read_permission: "leaders", amount_permission: "leaders")
    with_accounting { get edit_accounting_rule_payment_plan_path(@rule, @nancy) }
    assert_select ".card-header .text-muted", text: /On this rule's settings only admins see the plan/

    @rule.update!(read_permission: "admin", amount_permission: "admin")
    with_accounting { get edit_accounting_rule_payment_plan_path(@rule, @nancy) }
    assert_select ".card-header .text-muted", text: /On this rule's settings only admins see the plan/
    assert_select ".card-header .text-muted", text: /amounts/, count: 0
  end

  test "a row ticked Remove stays ticked when the save fails, and goes on the next save" do
    sign_in @laura.user
    first, last = @rule.person_milestones.where(person: @nancy).to_a
    rows = ->(last_date) { { "0" => { id: first.id, name: first.name, due_on: first.due_on.iso8601, balance_at_most: "250", _destroy: "1" },
                             "1" => { id: last.id, name: last.name, due_on: last_date, balance_at_most: "0" } } }

    with_accounting { patch accounting_rule_payment_plan_path(@rule, @nancy), params: { plan: { rows: rows.call("") } } }
    assert_response :unprocessable_content
    assert_select "input[type=hidden][value=?]", first.id
    assert_select "input[type=checkbox][name=?][checked]", "plan[rows][0][_destroy]"

    with_accounting { patch accounting_rule_payment_plan_path(@rule, @nancy), params: { plan: { rows: rows.call("2099-12-01") } } }
    assert_redirected_to person_accounting_path(@nancy)
    assert_equal [ "Last payment" ], @rule.person_milestones.where(person: @nancy).map(&:name)
  end

  test "every bad row's errors show at once" do
    sign_in @laura.user

    with_accounting do
      patch accounting_rule_payment_plan_path(@rule, @janet), params: { plan: { rows: {
        "0" => { name: "First payment", due_on: "", balance_at_most: "100" },
        "1" => { name: "Second payment", due_on: "2099-10-01", balance_at_most: "100", balance_at_most_percent: "10" } } } }
    end

    assert_response :unprocessable_content
    assert_select ".alert-danger li", text: /First payment: Due on can't be blank/
    assert_select ".alert-danger li", text: /Second payment: Give the balance at most as an amount or a percent, not both/
  end

  test "saving fires update hooks only for rows that changed" do
    Thread.current[:accounting_plan_updates] = []
    Hook.create!(name: "Plan changed", event: "accounting_person_milestones - update", code: "Thread.current[:accounting_plan_updates] << model.name")
    sign_in @laura.user
    first, last = @rule.person_milestones.where(person: @nancy).to_a

    with_accounting do
      patch accounting_rule_payment_plan_path(@rule, @nancy), params: { plan: { rows: {
        "0" => { id: first.id, name: first.name, due_on: first.due_on.iso8601, balance_at_most: "250", note: "Moved by a week" },
        "1" => { id: last.id, name: last.name, due_on: last.due_on.iso8601, balance_at_most: "0" } } } }
    end

    assert_redirected_to person_accounting_path(@nancy)
    assert_equal [ "First payment" ], Thread.current[:accounting_plan_updates]
  ensure
    Thread.current[:accounting_plan_updates] = nil
  end

  test "admins see the plan mark, the note on the plan page, and the On a plan filter" do
    sign_in @laura.user

    with_accounting { get person_accounting_path(@nancy) }
    assert_select "##{dom_id(result_for(@rule, @nancy))}" do
      assert_select ".badge", text: "On a plan"
      assert_select "a[href=?]", edit_accounting_rule_payment_plan_path(@rule, @nancy), text: "Payment plan"
    end

    with_accounting { get accounting_rule_path(@rule, plan: "1") }
    assert_select "label", text: "Only people on a payment plan"
    assert_select "td", text: /Nancy/
    assert_select "td", text: /Janet/, count: 0
    assert_select "td .badge", text: "On a plan"

    with_accounting { get edit_accounting_rule_payment_plan_path(@rule, @nancy) }
    assert_response :success
    assert_select "input[value=?]", "Agreed with the family by phone"
    # The form's fields name the rows the way update reads them.
    assert_select "input[name=?][value=?]", "plan[rows][0][name]", "First payment"
    assert_select "input[name=?]", "plan[rows][3][due_on]"
    assert_select "button", text: "Remove plan"
  end

  test "only admins open or change a plan" do
    [ @nancy, @margaret, @andrew ].each do |viewer|
      sign_in viewer.user
      with_accounting do
        get edit_accounting_rule_payment_plan_path(@rule, @nancy)
        assert_not_equal 200, response.status, "#{viewer.first_name} opened the plan"
        patch accounting_rule_payment_plan_path(@rule, @nancy), params: { plan: { rows: { "0" => { name: "Free", due_on: "2099-01-01", balance_at_most: "0" } } } }
        delete accounting_rule_payment_plan_path(@rule, @nancy)
      end
      sign_out viewer.user
    end

    assert_equal [ "First payment", "Last payment" ], @rule.person_milestones.where(person: @nancy).map(&:name)
  end

  test "an admin sets up a plan, changes it and removes it; each works the result out again" do
    sign_in @laura.user

    assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ @rule, [ @janet.id ] ]) do
      with_accounting do
        patch accounting_rule_payment_plan_path(@rule, @janet), params: { plan: { rows: {
          "0" => { name: "First payment", due_on: "2099-09-01", balance_at_most: "200", note: "Hardship" },
          "1" => { name: "", due_on: "", balance_at_most: "" } } } }
      end
    end
    assert_redirected_to person_accounting_path(@janet)
    plan = @rule.person_milestones.where(person: @janet).to_a
    assert_equal [ [ "First payment", 20_000, "Hardship", @laura.id ] ], plan.map { |row| [ row.name, row.balance_at_most_cents, row.note, row.created_by_id ] }

    with_accounting do
      patch accounting_rule_payment_plan_path(@rule, @janet), params: { plan: { rows: {
        "0" => { id: plan.first.id, name: "First payment", due_on: "2099-09-01", balance_at_most_percent: "10", balance_at_most: "" } } } }
    end
    assert_equal [ [ nil, 10 ] ], @rule.person_milestones.where(person: @janet).pluck(:balance_at_most_cents, :balance_at_most_percent)

    with_accounting do
      patch accounting_rule_payment_plan_path(@rule, @janet), params: { plan: { rows: { "0" => { id: plan.first.id, name: "First payment", due_on: "" } } } }
    end
    assert_response :unprocessable_content
    assert_select ".alert-danger", text: /Due on can't be blank/

    assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ @rule, [ @janet.id ] ]) do
      with_accounting { delete accounting_rule_payment_plan_path(@rule, @janet) }
    end
    assert_redirected_to person_accounting_path(@janet)
    assert_not @rule.person_milestones.exists?(person: @janet)
  end

  test "ticking Remove on every row removes the plan" do
    sign_in @laura.user
    rows = @rule.person_milestones.where(person: @nancy).to_a

    with_accounting do
      patch accounting_rule_payment_plan_path(@rule, @nancy), params: { plan: { rows: rows.each_with_index.to_h { |row, index|
        [ index.to_s, { id: row.id, name: row.name, due_on: row.due_on.iso8601, balance_at_most: row.balance_at_most, _destroy: "1" } ] } } }
    end

    assert_redirected_to person_accounting_path(@nancy)
    assert_match "follows the rule's milestones again", flash[:notice]
    assert_not @rule.person_milestones.exists?(person: @nancy)
  end

  test "the routes refuse while the feature is off" do
    sign_in @laura.user

    with_accounting(false) { get edit_accounting_rule_payment_plan_path(@rule, @nancy) }

    assert_redirected_to root_path
  end
end
