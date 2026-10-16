require "test_helper"
require_relative "../support/commitments_world"

# SignupsSummary's commitments copy the own-page rule of
# PersonCommitmentsPolicy#visible_commitments (less ended commitments) so it
# can leave ended ones out before checking them. These tests catch the two
# drifting apart.
class SignupsSummaryTest < ActiveSupport::TestCase
  include CommitmentsWorld

  setup do
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_commitments_world
  end

  # A person who owes (member), a parent of someone who owes in the grouped
  # commitment but not the ungrouped one (organizer), and people unrelated
  # to the Members commitments.
  test "lists what the person's own commitments page shows, less ended commitments" do
    create_world_commitment("Shifts", group_relationship_type: @parent_of)
    create_world_commitment("Dues")
    create_world_commitment("Crew hours", owing_team: @crew)
    create_world_commitment("Spring shifts", group_relationship_type: @parent_of, starts_on: Date.new(2026, 3, 1), ends_on: Date.new(2026, 9, 30))
    create_world_commitment("Spring dues", starts_on: Date.new(2026, 3, 1), ends_on: Date.new(2026, 9, 30))
    create_world_commitment("Other", team: @other_org, owing_team: @other_org)

    expected = {
      member: %w[ Dues Shifts ],
      organizer: [ "Crew hours", "Shifts" ],
      crew_manager: [ "Crew hours" ],
      outsider: %w[ Other ]
    }
    with_feature do
      expected.each do |name, titles|
        viewer = person(name)
        policy_titles = PersonCommitmentsPolicy.new(viewer.user, viewer).visible_commitments
          .reject { |commitment| commitment.ends_on < Date.current }.map(&:title)

        assert_equal titles.sort, summary_titles(viewer).sort, "summary for #{name}"
        assert_equal policy_titles, summary_titles(viewer), "summary and policy for #{name}"
      end
    end
  end

  test "ended commitments add no queries" do
    create_world_commitment("Shifts", group_relationship_type: @parent_of)

    with_feature do
      before = count_queries { SignupsSummary.new(person(:member).user).commitments }

      # Each owed by its own team, so their checks can't share cached
      # queries, and outside Club, so they don't grow the current
      # commitment's tree.
      teams = (0...10).map { |index| create_world_team("Old #{index}", parent: @other_org) }
      other_org = @other_org.reload
      teams.each_with_index do |team, index|
        create_world_commitment("Old #{index}", team: other_org, owing_team: team,
          group_relationship_type: (@parent_of if index.even?), starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 9, 30))
      end

      after = count_queries { SignupsSummary.new(person(:member).user).commitments }
      assert_equal before, after
    end
  end

  private

  def summary_titles(viewer)
    SignupsSummary.new(viewer.user).commitments.map { |item| item.progress.commitment.title }
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[ SCHEMA TRANSACTION ]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
