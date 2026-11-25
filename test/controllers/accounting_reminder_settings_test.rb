require "test_helper"
require_relative "../support/accounting_rules_world"

# The rule form's Reminders tab and the rule page's reminders line.
class AccountingReminderSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include AccountingRulesWorld

  setup do
    host! "localhost"
    @team = create_rule_team("Robotics")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    add_charge("58", "I1", total: 40_000, balance: 10_000)
    @rule = create_rule(read_permission: "family", amount_permission: "family", team: @team)
    evaluate(@rule)
    sign_in @laura.user
  end

  test "admins set a rule's reminders on its Reminders tab" do
    with_accounting { get edit_accounting_rule_path(@rule, tab: "reminders") }
    assert_select "a.nav-link.active", text: "Reminders"
    assert_select "input[type=radio][name=?][value=both][checked]", "accounting_rule[remind_to]"
    assert_select "input[type=radio][name=?][value=name_only][checked]", "accounting_rule[reminder_level]"

    with_accounting do
      patch accounting_rule_path(@rule), params: { tab: "reminders", accounting_rule: {
        remind_days_before: "3", overdue_every_days: "7", remind_to: "person", reminder_level: "everything" } }
    end
    assert_redirected_to edit_accounting_rule_path(@rule, tab: "reminders")
    @rule.reload
    assert_equal [ 3, 7, "person", "everything" ], [ @rule.remind_days_before, @rule.overdue_every_days, @rule.remind_to, @rule.reminder_level ]

    with_accounting { patch accounting_rule_path(@rule), params: { tab: "reminders", accounting_rule: { overdue_every_days: "0" } } }
    assert_response :unprocessable_content
  end

  test "the rule page tells admins how reminders go and when one was last sent" do
    @rule.update!(remind_days_before: 3, overdue_every_days: 7)
    AccountingReminder.create!(rule: @rule, person: @nancy, recipient: @nancy, milestone_key: "overdue", sent_at: Time.zone.local(2026, 3, 1, 8))

    with_accounting { get accounting_rule_path(@rule) }

    assert_select "p", text: "Reminders: 3 days before each milestone, then every 7 days while overdue; last sent Mar 01"
  end

  test "members don't see the reminders line" do
    @rule.update!(remind_days_before: 3)
    sign_out @laura.user
    sign_in @nancy.user

    with_accounting { get accounting_rule_path(@rule) }

    assert_response :success
    assert_no_match "Reminders:", response.body
  end
end
