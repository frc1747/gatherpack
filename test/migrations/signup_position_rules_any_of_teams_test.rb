require "test_helper"
require_relative "../support/signups_world"
require Rails.root.join("db/migrate/20261011210204_signup_position_rules_any_of_teams")

# Runs the migration down and back up inside the test's transaction, with
# rules made the old way (one team each, any number per kind).
class SignupPositionRulesAnyOfTeamsTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    @sheet = create_world_sheet
    @bar = @sheet.signup_positions.create!(name: "Bar")
    @grill = @sheet.signup_positions.create!(name: "Grill")
    @migration = SignupPositionRulesAnyOfTeams.new
    @migration.verbose = false
    @migration.migrate(:down)
  end

  teardown do
    SignupPositionRule.reset_column_information
  end

  test "folds each position's rules into one per kind" do
    concessions_rule = old_rule(@bar, :team, team_id: @concessions.id, at: 3.minutes.ago)
    old_rule(@bar, :team, team_id: @students.id, at: 2.minutes.ago)
    old_rule(@bar, :team, team_id: @concessions.id, at: 1.minute.ago)
    license_rule = old_rule(@bar, :badge, badge_ids: [ @license_badge.id ], at: 3.minutes.ago)
    old_rule(@bar, :badge, badge_ids: [ @organizer_badge.id, @license_badge.id ], at: 2.minutes.ago)
    first_age = old_rule(@bar, :age, min_age: 16, at: 3.minutes.ago)
    old_rule(@bar, :age, max_age: 30, at: 2.minutes.ago)
    grill_team = old_rule(@grill, :team, team_id: @club.id, at: 1.minute.ago)

    @migration.migrate(:up)
    SignupPositionRule.reset_column_information

    assert_equal [ concessions_rule, license_rule, first_age ].sort, SignupPositionRule.where(signup_position: @bar).pluck(:id).sort
    assert_equal [ @concessions.id, @students.id ].sort, SignupPositionRule.find(concessions_rule).team_ids.sort
    assert_equal [ @license_badge.id, @organizer_badge.id ].sort, SignupPositionRule.find(license_rule).badge_ids.sort
    assert_equal [ 16, nil ], SignupPositionRule.find(first_age).then { |rule| [ rule.min_age, rule.max_age ] }
    assert_equal [ @club.id ], SignupPositionRule.find(grill_team).team_ids
    assert_not_includes SignupPositionRule.column_names, "team_id"

    @migration.migrate(:down)
    assert_equal [ @club.id ], select_team_ids(grill_team)
    assert_includes [ [ @concessions.id ], [ @students.id ] ], select_team_ids(concessions_rule), "keeps one of the merged teams"
  end

  private

  def old_rule(position, kind, at:, team_id: nil, badge_ids: [], min_age: nil, max_age: nil)
    id = SecureRandom.uuid
    connection.execute(<<~SQL)
      INSERT INTO signup_position_rules (id, signup_position_id, kind, badge_ids, min_age, max_age, team_id, created_at, updated_at)
      VALUES (#{[ id, position.id, SignupPositionRule.kinds[kind] ].map { |v| connection.quote(v) }.join(", ")},
        ARRAY[#{badge_ids.map { |b| connection.quote(b) }.join(", ")}]::uuid[],
        #{connection.quote(min_age)}, #{connection.quote(max_age)}, #{connection.quote(team_id)}, #{connection.quote(at)}, #{connection.quote(at)})
    SQL
    id
  end

  def select_team_ids(id)
    connection.select_values("SELECT team_id FROM signup_position_rules WHERE id = #{connection.quote(id)}")
  end

  def connection
    ActiveRecord::Base.connection
  end
end
