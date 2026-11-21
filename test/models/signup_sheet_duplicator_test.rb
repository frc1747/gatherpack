require "test_helper"
require_relative "../support/signups_world"

class SignupSheetDuplicatorTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(description: "Help run the stand.", contact: "Pat", created_by: person(:admin),
      names_permission: :organizers, on_behalf_of_mode: :anyone, cancel_cutoff_hours: 4, reminder_days: 5)
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 3, question: "Shift?", question_required: true)
    @cashier.signup_position_rules.create!(kind: :age, min_age: 14)
    @sheet.signup_positions.create!(name: "Pizza", kind: :items, unit: "pizzas")
    @sheet.signup_audience_rules.create!(effect: :include, target_type: :team, team: @students, created_by: person(:admin))
    @sheet.signup_sheet_organizers.create!(person: person(:worker))
    Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:student), answer: "Early")
  end

  teardown do
    @restore_settings&.call
  end

  test "copies the setup and leaves behind dates, slots and sign-ups" do
    copy = SignupSheets::Duplicator.call(@sheet, created_by: person(:worker))

    assert_not_equal @sheet, copy
    assert_equal "#{@sheet.title} (copy)", copy.title
    assert copy.draft?
    %w[ team_id description contact names_permission on_behalf_of_mode cancel_cutoff_hours reminder_days ].each do |attribute|
      assert_equal @sheet.public_send(attribute), copy.public_send(attribute), attribute
    end
    assert_equal [ "Cashier", "Pizza" ], copy.signup_positions.map(&:name)
    assert_equal [ 3, nil ], copy.signup_positions.map(&:capacity)
    assert_equal [ "pizzas" ], copy.signup_positions.filter_map(&:unit)
    copied_rule = copy.signup_positions.first.signup_position_rules.sole
    assert_predicate copied_rule, :age?
    assert_equal 14, copied_rule.min_age
    assert_equal [ [ "include", "team", @students.id ] ], copy.signup_audience_rules.map { |r| [ r.effect, r.target_type, r.team_id ] }
    assert_equal [ person(:worker).id ], copy.signup_audience_rules.map(&:created_by_id)
    assert_equal [ person(:admin), person(:worker) ].map(&:id).sort, copy.signup_sheet_organizers.pluck(:person_id).sort

    assert_empty copy.signup_sheet_events
    assert_empty copy.signup_slots
    assert_empty copy.signups
    assert_equal 1, @sheet.reload.signups.count
    assert_equal 2, @sheet.signup_positions.count
  end

  test "leaves out relationship types that members can now add themselves" do
    @sheet.update_column(:others_relationship_type_ids, [ @parent_of.id, @sibling_of.id ])
    @sibling_of.update_column(:permission, RelationshipType.permissions.fetch("added_by_participant"))

    copy = SignupSheets::Duplicator.call(@sheet, created_by: person(:worker))

    assert_equal [ @parent_of.id ], copy.others_relationship_type_ids
  end

  test "makes nothing when any part fails" do
    @cashier.update_column(:name, "")

    assert_no_difference [ "SignupSheet.count", "SignupPosition.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) { SignupSheets::Duplicator.call(@sheet, created_by: person(:worker)) }
    end
  end
end
