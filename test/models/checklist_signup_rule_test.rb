require "test_helper"
require_relative "../support/signups_world"

# The checklist kind of sign-up position rule (checklists spec §10.3).
class ChecklistSignupRuleTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    travel_to Time.zone.parse("2026-10-11 12:00")
    @restore_checklists = apply_settings(feature_checklists: "true")
    build_signups_world
    @sheet = create_world_sheet
    @position = @sheet.signup_positions.create!(name: "Driver")
    @checklist = Checklist.create!(title: "Trip", team: @club, status: :active, starts_on: Date.new(2026, 9, 1),
      ends_on: Date.new(2027, 6, 30), created_by: person(:admin))
    item = @checklist.checklist_items.new(kind: "badge", label: "License")
    item.config_params = { badge_ids: [ @license_badge.id ] }
    item.save!
    @item = item
    Checklists::Refresher.new(@checklist.reload, silent: true).call
  end

  teardown { @restore_checklists&.call }

  def overall(name)
    ChecklistResult.find_by!(checklist: @checklist, item_id: nil, person: person(name))
  end

  test "people who finish the checklist pass; people who haven't get the reason" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)

    assert_equal "met", overall(:worker).status
    assert_nil rule.check(person(:worker), @event)
    assert_equal "not_met", overall(:student).status
    assert_equal "Needs Trip: Complete", rule.check(person(:student), @event)
    assert_equal "Needs Trip: Complete", rule.description
  end

  test "in progress passes only when the rule accepts it" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    overall(:student).update!(status: "pending")

    assert_equal "Needs Trip: Complete", rule.check(person(:student), @event)

    rule.update!(accept_pending: true)
    assert_nil rule.reload.check(person(:student), @event)
    assert_equal "Needs Trip: Complete or In Progress", rule.description
    assert_equal "Needs Trip: Complete or In Progress", rule.check(person(:student2), @event), "not started still fails"
  end

  test "an exempt overall passes, and so does an item that doesn't apply" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    overall(:student2).update!(status: "exempt")
    assert_nil rule.check(person(:student2), @event)

    @checklist.checklist_rules.create!(item: @item, effect: :exclude, target_type: :person, person: person(:student))
    Checklists::Refresher.new(@checklist.reload, silent: true).call
    assert_equal "exempt", ChecklistResult.find_by!(checklist: @checklist, item: @item, person: person(:student)).status
    assert_nil rule.reload.check(person(:student), @event)
  end

  test "people the checklist doesn't cover never pass" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist, accept_pending: true)

    assert_nil rule.checklist_status(person(:outsider))
    assert_equal "Needs Trip: Complete or In Progress", rule.check(person(:outsider), @event)
  end

  test "a person must pass the checklist rule and every other rule, any one badge being enough within a badge rule" do
    @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @organizer_badge.id, @license_badge.id ])
    @position.signup_position_rules.create!(kind: :age, min_age: 18)
    @position.reload

    assert @position.eligible?(person(:worker), @event, viewer: person(:worker))

    BadgeAssignment.create!(badge: @organizer_badge, person: person(:student))
    assert_equal [ "Needs Trip: Complete", "Must be 18 or older on Oct 24" ], @position.reload.eligibility_failures(person(:student), @event, viewer: person(:student))

    BadgeAssignment.where(badge: [ @organizer_badge, @license_badge ], person: person(:worker)).destroy_all
    Checklists::Refresher.new(@checklist.reload, silent: true).call
    assert_equal [ "Needs Trip: Complete", "Needs the Alcohol License or Sheet Organizer badge" ],
      @position.reload.eligibility_failures(person(:worker), @event, viewer: person(:worker))
  end

  test "a rule follows the checklist's refresh" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    BadgeAssignment.create!(badge: @license_badge, person: person(:student))

    assert overall(:student).stale?, "the badge marks the result for recomputing"
    assert_equal "Needs Trip: Complete", rule.check(person(:student), @event), "until the refresh runs"

    Checklists::Refresher.new(@checklist.reload).call
    assert_nil rule.reload.check(person(:student), @event)
  end

  test "people with no stored result yet, and results past their age, are computed when checked" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    ChecklistResult.where(checklist: @checklist, person: person(:worker)).delete_all
    assert_nil rule.check(person(:worker), @event)
    assert_equal "met", overall(:worker).status

    BadgeAssignment.where(badge: @license_badge, person: person(:worker)).delete_all
    overall(:worker).update_columns(computed_at: 2.days.ago)
    assert_equal "Needs Trip: Complete", rule.reload.check(person(:worker), @event)
  end

  test "a sign-up is refused with the reason" do
    @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    signup = Signup.new(signup_slot: slot_for(@position), person: person(:student), signed_up_by: person(:student), on_behalf_of: person(:student))

    error = assert_raises(ActiveRecord::RecordInvalid) { signup.check_placement!(by: person(:student)) }
    assert_includes error.record.errors[:base], "Needs Trip: Complete"
  end

  test "with checklists turned off the rule fails with its reason" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)

    with_settings(feature_checklists: "false") do
      assert_equal "Needs Trip: Complete (checklists are turned off)", rule.check(person(:worker), @event)
    end
  end

  test "needs a checklist, and other kinds don't keep one" do
    rule = @position.signup_position_rules.new(kind: :checklist)
    assert_not rule.valid?
    assert_includes rule.errors.full_messages, "Choose a checklist"

    badge_rule = @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ], checklist: @checklist, accept_pending: true)
    assert_nil badge_rule.checklist_id
    assert_not badge_rule.accept_pending?
  end

  test "one checklist rule per position" do
    @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    rule = @position.signup_position_rules.new(kind: :checklist, checklist: @checklist)

    assert_not rule.valid?
    assert_includes rule.errors[:kind], "This position already has a checklist rule; change it instead"
  end

  test "a draft or archived checklist lets nobody through, with a fixed reason, and a draft's results aren't computed" do
    rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)

    @checklist.update!(status: :archived)
    assert_equal "Needs Trip: Complete (Trip is archived)", rule.reload.check(person(:worker), @event)

    @checklist.update!(status: :draft)
    ChecklistResult.where(checklist: @checklist).delete_all
    assert_equal "Needs Trip: Complete (Trip is a draft)", rule.reload.check(person(:worker), @event)
    assert_nil rule.checklist_status(person(:worker))
    assert_not ChecklistResult.exists?(checklist: @checklist)
    assert_empty Checklists::SignupSheetNeeds.new(@sheet, person(:student)).entries
  end

  test "housekeeping doesn't archive a checklist a sheet still needs, and says why" do
    @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)

    with_settings(checklists_archive_after: "30") do
      travel_to Date.new(2027, 8, 15) do
        assert_empty Checklists::Housekeeping.run[:archived]
        assert @checklist.reload.active?
        assert_includes @checklist.problems, "Ended, but not archived: the sign-up sheet Snack Stand still needs it"

        other = Checklist.create!(title: "Later", team: @club, status: :active, created_by: person(:admin))
        item = other.checklist_items.new(kind: "checklist", label: "Trip done")
        item.config_params = { checklist_id: @checklist.id }
        item.save!
        assert_includes @checklist.problems, "Ended, but not archived: Later and the sign-up sheet Snack Stand still need it"
        other.destroy!

        @sheet.update!(status: :archived)
        assert_equal [ @checklist ], Checklists::Housekeeping.run[:archived]
        assert @checklist.reload.archived?
      end
    end
  end

  test "housekeeping still archives checklists no sheet needs" do
    with_settings(checklists_archive_after: "30") do
      travel_to Date.new(2027, 8, 15) do
        assert_equal [ @checklist ], Checklists::Housekeeping.run[:archived]
      end
    end
  end

  test "a checklist a rule needs can't be deleted" do
    @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)

    assert_not @checklist.destroy
    assert_equal [ "Sign-up sheet Snack Stand (Driver) needs it; take it off there first" ], @checklist.errors.full_messages
    assert Checklist.exists?(@checklist.id)
  end
end
