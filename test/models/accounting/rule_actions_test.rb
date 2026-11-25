require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::RuleActionsTest < ActiveSupport::TestCase
  include AccountingRulesWorld

  setup do
    @restore_settings = SettingsTestHelper.apply(feature_badges: "true", feature_person_fields: "true")
    @team = create_rule_team("Robotics")
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @janet = create_rule_person("Janet", "Leverling", customer: "60")
    add_charge("58", "I1", total: 40_000, balance: 10_000)
    add_charge("60", "I2", total: 40_000, balance: 0)
    @rule = create_rule
    @paid_up = create_rule_badge("Dues Paid")
  end

  teardown do
    @restore_settings&.call
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

  test "deleting a source takes back what its rules' actions gave" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up)
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")
    evaluate(@rule)
    assert_equal 2, @paid_up.badge_assignments.count

    accounting_source.destroy!

    assert_not AccountingRule.exists?(@rule.id)
    assert_empty @paid_up.badge_assignments.reload
    assert_nil @nancy.reload.field_value(field)
  end

  test "only badges admins assign can be given" do
    self_service = create_rule_badge("Volunteer", permission: :added_by_admin_or_self)

    action = @rule.actions.build(action: "badge", badge: self_service)

    assert_not action.valid?
    assert_includes action.errors[:badge], "must be one only admins can assign"
  end

  test "two turned-on rules can't fill in one field; a turned-off copy is checked when turned on" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")
    other = create_rule("Fees")

    taken = other.actions.build(action: "person_field", person_field: field, write: "value")
    assert_not taken.valid?
    assert_includes taken.errors[:base], "Dues is already filled in by the rule 2027 Membership Dues. Two rules filling in one field " \
      "would keep overwriting each other: turn that rule off or remove its action first."

    copy = @rule.duplicate!
    assert_equal 1, copy.actions.count, "a turned-off Duplicate keeps the action"
    assert_not copy.update(enabled: true)
    assert_match "Dues is already filled in by the rule 2027 Membership Dues", copy.errors.full_messages.to_sentence

    @rule.update!(enabled: false)
    assert copy.update(enabled: true)
  end

  test "one rule fills in a field once" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.assign_attributes(actions_attributes: [ { action: "person_field", person_field_id: field.id, write: "label" },
      { action: "person_field", person_field_id: field.id, write: "value" } ])

    assert_not @rule.save
    assert_includes @rule.errors[:base], "Dues is filled in by more than one action"
  end

  test "the same badge on two rules is allowed and each takes back only its own" do
    @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    other = create_rule("Anyone")
    other_action = other.actions.create!(action: "badge", badge: @paid_up)

    assert_equal [ other ], @rule.actions.first.other_rules_giving_badge.to_a
    assert_equal [ @rule ], other_action.other_rules_giving_badge.to_a
    evaluate(@rule)
    evaluate(other)
    assert_equal 2, @paid_up.badge_assignments.count

    other.destroy!
    assert_equal [ @janet ], @paid_up.badge_assignments.reload.map(&:person)
  end

  test "each kind of action is skipped, not undone, while its feature is off" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")
    evaluate(@rule)

    with_settings(feature_badges: "false", feature_person_fields: "false") do
      pay_off("I1")
      seen = capture("person_fields - value changed") { evaluate(@rule) }
      assert_empty seen
      assert_equal [ @janet ], @paid_up.badge_assignments.reload.map(&:person), "no badge added, none taken away"
      assert_equal "Partly paid", @nancy.reload.field_value(field)
    end

    evaluate(@rule)
    assert_equal "Paid", @nancy.reload.field_value(field)
    assert_equal 2, @paid_up.badge_assignments.reload.count
  end

  test "a badge action keeps no field settings" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")

    action = @rule.actions.create!(action: "badge", badge: @paid_up, person_field: field, write: "label")

    assert_equal [ nil, nil ], [ action.person_field_id, action.write ]
  end

  test "turning a rule off takes back its badges and field values; turning it on gives them again" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")
    evaluate(@rule)
    assert_equal [ @janet ], @paid_up.badge_assignments.map(&:person)

    @rule.update!(enabled: false)

    assert_empty @paid_up.badge_assignments.reload
    assert_nil result_for(@rule, @janet).badge_assignment_id
    assert_equal [ nil, nil ], [ @janet, @nancy ].map { |person| person.reload.field_value(field) }

    @rule.update!(enabled: true)
    evaluate(@rule)

    assert_equal [ @janet ], @paid_up.badge_assignments.reload.map(&:person)
    assert_equal [ "Paid", "Partly paid" ], [ @janet, @nancy ].map { |person| person.reload.field_value(field) }
  end

  test "deleting a turned-off rule has nothing left to take back" do
    field = PersonField.create!(name: "Dues", data_type: :string, write_permission: "admin")
    @rule.actions.create!(action: "person_field", person_field: field, write: "label")
    evaluate(@rule)
    @rule.update!(enabled: false)
    @nancy.set_field_value(field, "Waived")

    seen = capture("person_fields - value changed") { @rule.destroy! }

    assert_empty seen
    assert_equal "Waived", @nancy.reload.field_value(field)
  end

  test "a Duplicate takes over: last season's badges go and the copy gives them to people who meet it now" do
    field = PersonField.create!(name: "Season Dues", data_type: :string, write_permission: "admin")
    old = create_rule("2026-27 Dues", filters: { "txn_date_from" => "2026-07-01", "txn_date_to" => "2027-06-30" })
    old.actions.create!(action: "badge", badge: @paid_up, condition: { "values" => [ "paid" ] })
    old.actions.create!(action: "person_field", person_field: field, write: "label")
    evaluate(old)
    assert_equal [ @janet ], @paid_up.badge_assignments.map(&:person)
    assert_equal "Paid", @janet.reload.field_value(field)

    copy = old.duplicate!
    assert_equal "2027-28 Dues", copy.name
    add_charge("58", "I3", total: 40_000, balance: 0, txn_date: Date.new(2027, 9, 1))
    add_charge("60", "I4", total: 40_000, balance: 40_000, txn_date: Date.new(2027, 9, 1))

    old.update!(enabled: false)
    assert_empty @paid_up.badge_assignments.reload, "last season's badges are taken back"
    assert copy.update(enabled: true), copy.errors.full_messages.to_sentence
    evaluate(copy)

    assert_equal [ @nancy ], @paid_up.badge_assignments.reload.map(&:person)
    assert_equal result_for(copy, @nancy).badge_assignment, @paid_up.badge_assignments.sole
    assert_equal [ "Not yet paid", "Paid" ], [ @janet, @nancy ].map { |person| person.reload.field_value(field) }

    seen = capture("person_fields - value changed") { old.destroy! }
    assert_empty seen, "deleting last season's rule leaves this season's values alone"
    assert_equal [ @nancy ], @paid_up.badge_assignments.reload.map(&:person)
    assert_equal "Paid", @nancy.reload.field_value(field)
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
