require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::AddTeamMemberTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @open_team = create_world_team("Open")
    @open_team.update!(join_permission: :has_account)
    @approval_team = create_world_team("Approval")
    @approval_team.update!(join_permission: :requires_approval)
    @child = create_world_team("Alpha Child", parent: @alpha)
    Membership.create!(person: person(:beta_member), team: @open_team)
  end

  def add(viewer, member, team, **options)
    call_tool("add_team_member", user: user(viewer), person_id: person(member).neat_id, team_id: team.neat_id, **options)
  end

  test "an admin adds anyone, as a manager if asked, and gets the membership back" do
    result = add(:admin, :beta_member, @alpha, manager: true)

    membership = Membership.find_by!(person: person(:beta_member), team: @alpha)
    assert membership.manager?
    assert_equal membership, result.changed
    assert_equal [ membership.neat_id, true ], result.value.values_at("id", "manager")
    assert_equal @alpha.neat_id, result.value.dig("team", "id")
  end

  test "a new member isn't a manager unless asked" do
    assert_equal false, add(:admin, :beta_member, @alpha).value["manager"]
    assert_not Membership.find_by!(person: person(:beta_member), team: @alpha).manager?
  end

  test "a team manager adds someone they can see to their team or a child team, and may set manager" do
    assert_nil add(:alpha_manager, :alpha_member, @child, manager: true).error
    assert Membership.find_by!(person: person(:alpha_member), team: @child).manager?
  end

  test "a team manager can add to an admin-only team they manage: the policy doesn't look at it" do
    @alpha.update!(join_permission: :added_by_admin)
    Membership.where(person: person(:ward), team: @alpha).destroy_all
    Membership.create!(person: person(:ward), team: @child)

    assert_nil add(:alpha_manager, :ward, @alpha).error
  end

  test "a manager can't add to a team they don't manage" do
    assert_refused("Not found", Membership) { add(:alpha_manager, :alpha_member, @beta) }
    assert_refused("Not allowed", Membership) { add(:alpha_manager, :alpha_member, @open_team) }
  end

  test "a plain member can add themselves to an open team, never as a manager or anyone else" do
    assert_refused("Not allowed", Membership) { add(:alpha_member, :alpha_member, @open_team, manager: true) }
    assert_refused("Not allowed", Membership) { add(:alpha_member, :ward, @open_team) }

    result = add(:alpha_member, :alpha_member, @open_team)
    assert_nil result.error
    assert_equal false, result.value["manager"]
  end

  test "a plain member can't add themselves to any other kind of team" do
    assert_refused("Not allowed", Membership) { add(:alpha_member, :alpha_member, @approval_team) }
    %i[added_by_admin added_by_manager added_by_current_member].each do |permission|
      @alpha.update!(join_permission: permission)
      assert_refused("Not allowed", Membership) { add(:alpha_member, :ward, @alpha) }
    end
    assert_refused("Not found", Membership) { add(:alpha_member, :alpha_member, @beta) }
  end

  test "a plain member on another team can't see or add the person" do
    assert_refused("Not found", Membership) { add(:beta_member, :alpha_member, @beta) }
  end

  test "a guardian can't add their ward, even to an open team" do
    assert_refused("Not found", Membership) { add(:guardian, :ward, @open_team) }
    assert_nil add(:guardian, :guardian, @open_team).error
  end

  test "a duplicate returns the validation message" do
    assert_refused("Person is already a member of this team", Membership) { add(:admin, :alpha_member, @alpha) }
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "tm_nonsense", @access_badge.neat_id ].each do |bad|
      assert_refused("Not found", Membership) { call_tool("add_team_member", user: user(:admin), person_id: person(:ward).neat_id, team_id: bad) }
      assert_refused("Not found", Membership) { call_tool("add_team_member", user: user(:admin), person_id: bad, team_id: @beta.neat_id) }
    end
    assert_refused(/team_id/, Membership) { call_tool("add_team_member", user: user(:admin), person_id: person(:ward).neat_id) }
  end

  test "manager must be a boolean" do
    assert_refused(/manager/, Membership) { add(:admin, :ward, @beta, manager: "yes") }
  end

  test "a read token and the setting being off refuse it" do
    assert_refused("Not allowed", Membership) { add(:admin, :ward, @beta, scopes: "mcp_read") }
    assert_refused("Writes disabled", Membership) { add(:admin, :ward, @beta, writes_enabled: false) }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("memberships - create") { add(:admin, :ward, @beta) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, :beta_member, @alpha, true ],
      [ :alpha_manager, :alpha_member, @child, true ],
      [ :alpha_manager, :alpha_member, @child, false ],
      [ :alpha_manager, :alpha_member, @beta, false ],
      [ :alpha_manager, :alpha_member, @open_team, false ],
      [ :alpha_member, :alpha_member, @open_team, false ],
      [ :alpha_member, :alpha_member, @open_team, true ],
      [ :alpha_member, :ward, @open_team, false ],
      [ :alpha_member, :alpha_member, @approval_team, false ],
      [ :alpha_member, :ward, @alpha, false ],
      [ :beta_member, :alpha_member, @beta, false ],
      [ :guardian, :guardian, @open_team, false ],
      [ :guardian, :guardian, @alpha, false ]
    ].each do |viewer, member, team, manager|
      page = page_changes_rows?(Membership, as: user(viewer)) do
        post team_memberships_path(team), params: { membership: { person_id: person(member).id, manager: manager } }
      end
      tool = changes_rows?(Membership) { add(viewer, member, team, manager: manager) }

      assert_equal page, tool, "#{viewer} adding #{member} to #{team.name}, manager: #{manager}"
    end
  end

  # The one difference: the team route's POST doesn't check the person, though its form only offers managed people.
  test "it refuses a person the manager can't see, where a hand-made POST goes through" do
    page = page_changes_rows?(Membership, as: user(:alpha_manager)) do
      post team_memberships_path(@alpha), params: { membership: { person_id: person(:beta_member).id } }
    end

    assert page
    assert_refused("Not found", Membership) { add(:alpha_manager, :beta_member, @alpha) }
  end
end
