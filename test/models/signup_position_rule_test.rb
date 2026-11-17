require "test_helper"
require_relative "../support/signups_world"

class SignupPositionRuleTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @sheet = create_world_sheet
    @position = @sheet.signup_positions.create!(name: "Bartender")
  end

  test "badge rule" do
    rule = @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id, "" ])

    assert_nil rule.check(person(:worker), @event)
    assert_equal "Needs the Alcohol License badge", rule.check(person(:student), @event)

    rule.update!(badge_ids: [ @license_badge.id, @organizer_badge.id ])
    assert_equal "Needs the Alcohol License or Sheet Organizer badge", rule.check(person(:student), @event)
  end

  test "a badge rule ignores deleted badges, and fails once none is left" do
    rule = @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id, @organizer_badge.id ])

    @organizer_badge.destroy!
    assert_nil rule.reload.check(person(:worker), @event)
    assert_equal "Needs the Alcohol License badge", rule.check(person(:student), @event)
    assert_equal "Needs the Alcohol License badge", rule.description

    @license_badge.destroy!
    assert_equal "Needs a badge that no longer exists", rule.reload.check(person(:worker), @event)
    assert_equal "Needs a badge that no longer exists", rule.description
  end

  test "a team rule ignores deleted teams, and fails once none is left" do
    rule = @position.signup_position_rules.create!(kind: :team, team_ids: [ @concessions.id, @students.id ])

    @students.destroy!
    assert_nil rule.reload.check(person(:worker), @event)
    assert_equal "Must be in Concessions", rule.check(person(:student), @event)
    assert_equal "In Concessions", rule.description

    @concessions.destroy!
    assert_equal "Must be in a team that no longer exists", rule.reload.check(person(:worker), @event)
  end

  test "age rule uses the age on the event's date" do
    rule = @position.signup_position_rules.create!(kind: :age, min_age: 16)

    assert_equal "Must be 16 or older on Oct 24", rule.check(person(:student), @event), "turns 16 the day after"
    next_day = create_world_event("Next Day", Time.zone.parse("2026-10-25 09:00"))
    assert_nil rule.check(person(:student), next_day)

    rule.update!(min_age: 14, max_age: 17)
    assert_nil rule.check(person(:student), @event)
    assert_equal "Must be 14 to 17 on Oct 24", rule.check(person(:worker), @event)

    rule.update!(min_age: nil, max_age: 30)
    assert_equal "Must be 30 or younger on Oct 24", rule.check(person(:worker), @event)
  end

  test "age rule fails with no birthday on file" do
    rule = @position.signup_position_rules.create!(kind: :age, min_age: 18)

    assert_equal "Must be 18 or older (no birthday on file)", rule.check(person(:student2), @event)
  end

  test "who may see an age result: the person, an admin, or someone who manages them" do
    assert SignupPositionRule.age_visible_to?(person(:student), person(:student))
    assert SignupPositionRule.age_visible_to?(person(:admin), person(:student))
    Membership.create!(person: person(:concessions_manager), team: @students, manager: true)
    assert SignupPositionRule.age_visible_to?(person(:concessions_manager), person(:student))

    assert_not SignupPositionRule.age_visible_to?(person(:worker), person(:student)), "an organizer by badge"
    assert_not SignupPositionRule.age_visible_to?(person(:parent), person(:student)), "a parent"
    assert_not SignupPositionRule.age_visible_to?(nil, person(:student))
  end

  test "an age rule isn't checked for an organizer who may not see the result, and is hidden from others" do
    with_organizer_grants("Sheet Organizer > Club") do
      @sheet.signup_sheet_organizers.create!(person: person(:worker))
      rule = @position.signup_position_rules.create!(kind: :age, min_age: 16)

      [ person(:student), person(:student2), person(:sibling) ].each do |someone|
        assert_nil rule.check_for(someone, @event, person(:worker))
        assert rule.unchecked_for?(someone, person(:worker))
      end
      assert_equal SignupPositionRule::AGE_HIDDEN_REASON, rule.check_for(person(:student), @event, person(:parent))
      assert_equal SignupPositionRule::AGE_HIDDEN_REASON, rule.check_for(person(:student2), @event, person(:parent))
      assert_not rule.unchecked_for?(person(:student), person(:parent))

      assert_equal "Must be 16 or older on Oct 24", rule.check_for(person(:student), @event, person(:student))
      assert_equal "Must be 16 or older on Oct 24", rule.check_for(person(:student), @event, person(:admin))
      assert_not rule.unchecked_for?(person(:student), person(:admin))
    end
  end

  test "an age check works out each person once for one viewer" do
    with_organizer_grants("Sheet Organizer > Club") do
      @sheet.signup_sheet_organizers.create!(person: person(:worker))
      friend_of = RelationshipType.create!(parent_label: "Friend of", child_label: "Friend of", permission: :added_by_participant)
      Relationship.create!(parent: person(:worker), child: person(:student2), relationship_type: friend_of, created_by: person(:worker))
      Relationship.create!(parent: person(:worker), child: person(:sibling), relationship_type: @sibling_of, created_by: person(:admin))
      check = Signups::AgeCheck.new(@sheet, person(:worker))

      assert_equal %i[ shown unchecked family hidden ], [ person(:worker), person(:student), person(:student2), person(:sibling) ].map { |someone| check.mode_for(someone) }
      assert_equal :hidden, Signups::AgeCheck.new(@sheet, person(:parent)).mode_for(person(:student))
      assert_equal :shown, Signups::AgeCheck.new(@sheet, person(:admin)).mode_for(person(:student))

      @sheet.signup_sheet_organizers.where(person: person(:worker)).delete_all
      assert_equal :unchecked, check.mode_for(person(:student)), "kept for the page"
      assert_equal :hidden, Signups::AgeCheck.new(@sheet, person(:worker)).mode_for(person(:student))
    end
  end

  test "other rules are checked for everyone" do
    rule = @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ])

    assert_equal "Needs the Alcohol License badge", rule.check_for(person(:student), @event, person(:parent))
    assert_not rule.unchecked_for?(person(:student), person(:parent))
  end

  test "age rule needs a limit" do
    rule = @position.signup_position_rules.build(kind: :age)
    assert_not rule.valid?

    rule.assign_attributes(min_age: 18, max_age: 16)
    assert_not rule.valid?
  end

  test "team rule passes for the team and the teams below it" do
    rule = @position.signup_position_rules.create!(kind: :team, team_ids: [ @club.id ])
    assert_nil rule.check(person(:worker), @event)

    rule.update!(team_ids: [ @concessions.id ])
    assert_nil rule.check(person(:worker), @event)
    assert_equal "Must be in Concessions", rule.check(person(:student), @event)
    assert_equal "Must be in Concessions", rule.check(person(:parent), @event)
  end

  test "team rule passes for any of its teams, or a team below one" do
    grill = create_world_team("Grill", parent: @other_org)
    rule = @position.signup_position_rules.create!(kind: :team, team_ids: [ "", @students.id, @other_org.id ])

    assert_nil rule.check(person(:student), @event)
    Membership.create!(person: person(:parent), team: grill)
    assert_nil rule.check(person(:parent), @event), "in a team below Other Org"
    assert_equal "In Other Org or Students", rule.description
    assert_equal "Must be in Other Org or Students", rule.check(person(:worker), @event)

    rule.update!(team_ids: [ @students.id, @other_org.id, @concessions.id ])
    assert_equal "Must be in Concessions, Other Org, or Students", rule.check(person(:sibling), @event)
  end

  test "team rule needs a team" do
    assert_not @position.signup_position_rules.build(kind: :team, team_ids: [ "" ]).valid?
  end

  test "a position has one rule of each kind" do
    @position.signup_position_rules.create!(kind: :team, team_ids: [ @club.id ])
    second = @position.signup_position_rules.build(kind: :team, team_ids: [ @students.id ])

    assert_not second.valid?
    assert_equal [ "This position already has a team rule; change it instead" ], second.errors[:kind]
    assert @position.signup_position_rules.build(kind: :age, min_age: 18).valid?
    assert @sheet.signup_positions.create!(name: "Cook").signup_position_rules.build(kind: :team, team_ids: [ @club.id ]).valid?
  end

  test "a position lists every failing rule" do
    @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ])
    @position.signup_position_rules.create!(kind: :age, min_age: 21)

    assert_equal [ "Needs the Alcohol License badge", "Must be 21 or older on Oct 24" ], @position.eligibility_failures(person(:student), @event, viewer: person(:student))
    assert @position.eligible?(person(:worker), @event, viewer: person(:worker))
  end
end
