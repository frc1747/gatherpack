require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeds load on an empty database and are idempotent" do
    2.times { Rails.application.load_seed }

    badge = Badge.find_by!(name: "Test Badge")
    team = Team.find_by!(name: "Test Team")

    assert_equal 5, badge.badge_assignments.count
    assert badge.badge_assignments.all? { |assignment| assignment.person.all_teams.include?(team) }
    assert_equal 5, team.memberships.count
  end
end
