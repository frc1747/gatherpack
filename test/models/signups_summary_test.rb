require "test_helper"
require_relative "../support/commitments_world"
require_relative "../support/checklists_flag_helper"

# SignupsSummary's commitments copy the own-page rule of
# PersonCommitmentsPolicy#visible_commitments (less ended commitments) so it
# can leave ended ones out before checking them. These tests catch the two
# drifting apart.
class SignupsSummaryTest < ActiveSupport::TestCase
  include CommitmentsWorld
  include ChecklistsFlagHelper

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

  test "is the sign-ups and commitments card, with no checklists, while checklists are off" do
    create_world_commitment("Shifts")

    with_feature do
      summary = SignupsSummary.new(person(:member).user)
      assert_equal "My Sign-ups and Commitments", summary.title
      assert_not summary.checklists_enabled?
      assert_empty summary.checklists
      assert_equal %w[ Shifts ], summary_titles(person(:member))
    end
  end

  test "with checklists on, is the sign-ups and checklists card and leaves out commitments that are count items" do
    create_world_commitment("Dues")
    with_count_item_commitment("Crew shifts") do
      with_feature do
        assert_equal [ "Crew shifts", "Dues" ], summary_titles(person(:member)).sort

        with_checklists_on do
          summary = SignupsSummary.new(person(:member).user)
          assert_equal "My Sign-ups and Checklists", summary.title
          assert_equal %w[ Dues ], summary_titles(person(:member))
        end
      end
    end
  end

  private

  # Yields with a commitment titled `title` that is a checklist's count item:
  # a real one where the checklists feature is present, otherwise a commitment
  # made to answer checklist_item.
  def with_count_item_commitment(title)
    if Commitment.reflect_on_association(:checklist_item)
      checklist = Checklist.create!(title: "Eligibility", team: @club, status: :active, starts_on: Date.new(2026, 10, 1),
        ends_on: Date.new(2026, 10, 31), created_by: person(:admin))
      checklist.checklist_rules.create!(effect: :include, target_type: :team, team: @members)
      item = checklist.checklist_items.new(kind: "count", label: title)
      item.config_params = { base_amount: 2, unit: "shifts" }
      item.save!
      yield
    else
      commitment_id = create_world_commitment(title).id
      Commitment.define_method(:checklist_item) { id == commitment_id ? :item : nil }
      begin
        yield
      ensure
        Commitment.remove_method(:checklist_item)
      end
    end
  end

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
