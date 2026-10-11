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

    assert_equal "No birthday on file", rule.check(person(:student2), @event)
  end

  test "age rule needs a limit" do
    rule = @position.signup_position_rules.build(kind: :age)
    assert_not rule.valid?

    rule.assign_attributes(min_age: 18, max_age: 16)
    assert_not rule.valid?
  end

  test "team rule passes for the team and the teams below it" do
    rule = @position.signup_position_rules.create!(kind: :team, team: @club)
    assert_nil rule.check(person(:worker), @event)

    rule.update!(team: @concessions)
    assert_nil rule.check(person(:worker), @event)
    assert_equal "Must be in Concessions", rule.check(person(:student), @event)
    assert_equal "Must be in Concessions", rule.check(person(:parent), @event)
  end

  test "a position lists every failing rule" do
    @position.signup_position_rules.create!(kind: :badge, badge_ids: [ @license_badge.id ])
    @position.signup_position_rules.create!(kind: :age, min_age: 21)

    assert_equal [ "Needs the Alcohol License badge", "Must be 21 or older on Oct 24" ], @position.eligibility_failures(person(:student), @event)
    assert @position.eligible?(person(:worker), @event)
  end
end
