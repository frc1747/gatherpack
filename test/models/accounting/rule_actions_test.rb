require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::RuleActionsTest < ActiveSupport::TestCase
  include AccountingRulesWorld

  setup do
    @team = create_rule_team("Robotics")
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", customer: "60")
    add_charge("58", "I1", total: 40_000, balance: 10_000)
    add_charge("60", "I2", total: 40_000, balance: 0)
    @rule = create_rule
    @paid_up = create_rule_badge("Dues Paid")
  end

  test "a badge is added while the condition holds and removed when it stops" do
    action = @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })

    evaluate(@rule)

    assert_equal [ @janet ], @paid_up.badge_assignments.map(&:person)
    assert_equal @paid_up.badge_assignments.sole, result_for(@rule, @janet).badge_assignment
    assert_nil result_for(@rule, @nancy).badge_assignment_id

    pay_off("I1")
    evaluate(@rule)
    assert_equal [ @janet, @nancy ].sort_by(&:first_name), @paid_up.badge_assignments.reload.map(&:person).sort_by(&:first_name)

    accounting_source.accounting_records.find_by!(external_id: "I2").update!(balance_cents: 5_000)
    evaluate(@rule)
    assert_equal [ @nancy ], @paid_up.badge_assignments.reload.map(&:person)
    assert_nil result_for(@rule, @janet).badge_assignment_id

    action.destroy!
    evaluate(@rule)
    assert_empty @paid_up.badge_assignments.reload, "a removed action takes back the badges it gave"
  end

  test "a badge given by hand is never taken away" do
    @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    by_hand = BadgeAssignment.create!(badge: @paid_up, person: @nancy)
    BadgeAssignment.create!(badge: @paid_up, person: @janet)

    evaluate(@rule)
    assert_nil result_for(@rule, @janet).badge_assignment_id, "Janet already has it, so the rule makes none"

    accounting_source.accounting_records.find_by!(external_id: "I2").update!(balance_cents: 5_000)
    evaluate(@rule)

    assert BadgeAssignment.exists?(by_hand.id)
    assert_equal [ @janet, @nancy ].sort_by(&:first_name), @paid_up.badge_assignments.map(&:person).sort_by(&:first_name)
  end

  test "a team badge skips people outside the team, noted in the result" do
    team_badge = create_rule_badge("Robotics Dues Paid", team: @team)
    @rule.actions.create!(action: "badge", badge: team_badge)

    evaluate(@rule)

    assert_equal [ @nancy ], team_badge.badge_assignments.map(&:person)
    assert_equal [ "Not given Robotics Dues Paid: not on its team, Robotics" ], result_for(@rule, @janet).detail(:action_notes)
    assert_nil result_for(@rule, @nancy).detail(:action_notes)
    assert_empty evaluate(@rule), "the note isn't a change"
  end

  test "a person who no longer qualifies loses the badge and the field" do
    field = PersonField.create!(name: "Dues", data_type: :string, read_permission: "family", write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up)
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")
    evaluate(@rule)
    assert_equal "Paid", @janet.reload.field_value(field)

    Accounting::CustomerLinks.new(accounting_source).unlink!(accounting_source.accounting_customer_links.find_by!(person: @janet))
    evaluate(@rule)

    assert_not BadgeAssignment.exists?(badge: @paid_up, person: @janet)
    assert_nil @janet.reload.field_value(field)
    assert BadgeAssignment.exists?(badge: @paid_up, person: @nancy)
  end

  test "deleting the rule takes back what its actions gave" do
    field = PersonField.create!(name: "Dues", data_type: :string, read_permission: "family", write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up)
    @rule.actions.create!(action: "person_field", person_field: field, write: "value")
    evaluate(@rule)

    @rule.destroy!

    assert_empty @paid_up.badge_assignments.reload
    assert_nil @nancy.reload.field_value(field)
  end

  test "a person field is written and cleared, firing value changed" do
    field = PersonField.create!(name: "Dues", data_type: :select, options: { "choices" => [ "Paid", "Partly paid" ] },
      read_permission: "family", write_permission: "admin")
    @rule.actions.create!(action: "person_field", person_field: field, write: "label", condition: { "values" => %w[ paid partial ] })
    seen = capture("person_fields - value changed") { evaluate(@rule) }

    assert_equal "Partly paid", @nancy.reload.field_value(field)
    assert_equal "Paid", @janet.reload.field_value(field)
    assert_equal [ [ "Janet", nil, "Paid", nil ], [ "Nancy", nil, "Partly paid", nil ] ],
      seen.map { |change| [ change.person.first_name, change.old_value, change.new_value, change.changed_by ] }.sort

    assert_empty capture("person_fields - value changed") { evaluate(@rule) }, "an unchanged value isn't written again"

    accounting_source.accounting_records.find_by!(external_id: "I1").update!(balance_cents: 40_000)
    cleared = capture("person_fields - value changed") { evaluate(@rule) }.sole
    assert_equal [ @nancy, "Partly paid", nil ], [ cleared.person, cleared.old_value, cleared.new_value ]
    assert_nil @nancy.reload.field_value(field)
  end

  test "a person field takes the value word or the amount" do
    word = PersonField.create!(name: "Dues Status", data_type: :string, write_permission: "admin")
    owed = PersonField.create!(name: "Dues Owed", data_type: :integer, write_permission: "admin")
    owed_text = PersonField.create!(name: "Dues Owed Text", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "person_field", person_field: word, write: "value")
    @rule.actions.create!(action: "person_field", person_field: owed, write: "amount", condition: { "op" => "gt", "amount_cents" => 0 })
    @rule.actions.create!(action: "person_field", person_field: owed_text, write: "amount")

    evaluate(@rule)

    assert_equal [ "partial", 100, "100.00" ], [ word, owed, owed_text ].map { |field| @nancy.reload.field_value(field) }
    assert_equal [ "paid", nil, "0.00" ], [ word, owed, owed_text ].map { |field| @janet.reload.field_value(field) }
  end

  test "conditions on the amount and on a count rule's count" do
    big = create_rule_badge("Owes a lot")
    @rule.actions.create!(action: "badge", badge: big, condition: { "op" => "gte", "amount_cents" => 10_000 })
    counted = create_rule("Invoices", kind: "count", filters: { "roles" => [ "charge" ] })
    many = create_rule_badge("Invoiced")
    counted.actions.create!(action: "badge", badge: many, condition: { "op" => "gt", "count" => 0 })

    evaluate(@rule)
    evaluate(counted)

    assert_equal [ @nancy ], big.badge_assignments.map(&:person)
    assert_equal [ @janet, @nancy ].sort_by(&:first_name), many.badge_assignments.map(&:person).sort_by(&:first_name)
  end

  test "an error result runs no actions and keeps what earlier runs did" do
    rule = create_rule("Eligible", kind: "custom", code: "Thread.current[:accounting_fail] ? raise('boom') : 'eligible'")
    rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "eligible" ] })
    evaluate(rule)
    assert_equal 2, @paid_up.badge_assignments.count

    Thread.current[:accounting_fail] = true
    evaluate(rule)

    assert_equal "error", result_for(rule, @nancy).value
    assert_equal 2, @paid_up.badge_assignments.count
  ensure
    Thread.current[:accounting_fail] = nil
  end

  test "result changed fires after the actions ran" do
    @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    Hook.create!(name: "Paid up", event: Accounting::Evaluation::EVENT,
      code: "Thread.current[:accounting_badges] << [model.person.first_name, model.new_value, model.person.badges.reload.map(&:name)]")
    Thread.current[:accounting_badges] = []

    evaluate(@rule)

    assert_equal [ [ "Janet", "paid", [ "Dues Paid" ] ], [ "Nancy", "partial", [] ] ], Thread.current[:accounting_badges].sort
  ensure
    Thread.current[:accounting_badges] = nil
  end

  test "actions aren't in the hook catalog" do
    assert_not Hook.catalog.any? { |entry| entry.start_with?("accounting_rule_actions") }
    assert_not Hook.catalog.any? { |entry| entry.start_with?("accounting_rule_badge_grants") }
  end

  test "nothing happens while the feature is off" do
    @rule.actions.create!(action: "badge", badge: @paid_up)

    with_accounting(false) { Accounting::EvaluateRuleJob.perform_now(@rule) }

    assert_empty @paid_up.badge_assignments
  end

  test "Duplicate keeps the actions" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")

    copy = @rule.duplicate!

    assert_equal [ [ "badge", @paid_up.id, nil, { "values" => [ "paid" ] } ], [ "person_field", nil, field.id, {} ] ],
      copy.actions.map { |action| [ action.action, action.badge_id, action.person_field_id, action.condition ] }.sort_by(&:first)
  end

  test "an action needs what it acts on and a whole condition; a rule gives one badge" do
    field = PersonField.create!(name: "Dues", data_type: :integer, write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up)

    assert_includes @rule.actions.build(action: "badge", badge: create_rule_badge("Second")).tap(&:validate).errors[:base], "A rule can give only one badge"
    assert @rule.actions.build(action: "person_field").tap(&:validate).errors.of_kind?(:person_field, :blank)
    assert_includes @rule.actions.build(action: "person_field", person_field: field, write: "label").tap(&:validate).errors[:write],
      "into a whole-number field can only be the amount"
    assert_includes @rule.actions.build(action: "badge", badge: @paid_up, condition_type: "values").tap(&:validate).errors[:condition],
      "needs at least one status"
    assert_includes @rule.actions.build(action: "badge", badge: @paid_up, condition_type: "amount", condition_op: "gt").tap(&:validate).errors[:condition],
      "needs an amount"
  end

  test "the form's condition fields build the stored condition" do
    action = @rule.actions.create!(action: "badge", badge: @paid_up, condition_type: "amount", condition_op: "gte", condition_amount: "150.50",
      condition_values: [ "" ])
    assert_equal({ "op" => "gte", "amount_cents" => 15_050 }, action.condition)
    assert_equal "Give Dues Paid when the amount is at least $150.50", action.description

    action.update!(condition_type: "values", condition_values: [ "", "paid", "partial" ])
    assert_equal({ "values" => %w[ paid partial ] }, action.reload.condition)

    action.update!(condition_type: "always", condition_values: [ "" ])
    assert_equal({}, action.reload.condition)
  end

  private
    def pay_off(external_id)
      accounting_source.accounting_records.find_by!(external_id: external_id).update!(balance_cents: 0)
    end

    def capture(event)
      seen = []
      Hook.create!(name: "Capture #{event}", event: event, code: "Thread.current[:accounting_seen] << model")
      Thread.current[:accounting_seen] = seen
      yield
      seen
    ensure
      Thread.current[:accounting_seen] = nil
      Hook.where(name: "Capture #{event}").delete_all
    end
end
