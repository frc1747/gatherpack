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

    assert_equal [ "Needs the Alcohol License badge", "Must be 21 or older on Oct 24" ], @position.eligibility_failures(person(:student), @event)
    assert @position.eligible?(person(:worker), @event)
  end
end
