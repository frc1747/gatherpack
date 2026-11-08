require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemoveTeamMemberTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    @member = membership(:alpha_member, @alpha)
    @beta_membership = membership(:beta_member, @beta)
  end

  def membership(name, team)
    Membership.find_by!(person: person(name), team: team)
  end

  def remove(viewer, target, **options)
    call_tool("remove_team_member", user: user(viewer), membership_id: target.neat_id, **options)
  end

  test "it is marked destructive" do
    assert Mcp.tool("remove_team_member").annotations[:destructive_hint]
  end

  test "an admin removes anyone and gets the membership back" do
    result = remove(:admin, @beta_membership)

    assert_not Membership.exists?(@beta_membership.id)
    assert_equal @beta_membership, result.changed
    assert_equal [ @beta_membership.neat_id, true ], result.value.values_at("id", "removed")
    assert_equal person(:beta_member).neat_id, result.value.dig("person", "id")
    assert_equal @beta.neat_id, result.value.dig("team", "id")
  end

  test "a team manager removes a member of their team, or a child team" do
    child = create_world_team("Alpha Child", parent: @alpha)
    in_child = Membership.create!(person: person(:beta_member), team: child)

    assert_difference("Membership.count", -2) do
      assert_nil remove(:alpha_manager, @member).error
      assert_nil remove(:alpha_manager, in_child).error
    end
  end

  test "a manager's own last membership goes, as on the page" do
    own = membership(:alpha_manager, @alpha)

    assert_nil remove(:alpha_manager, own).error
    assert_not Membership.exists?(own.id)
    assert_empty @alpha.managers
  end

  test "a plain member can't remove themselves or a teammate" do
    assert_refused("Not allowed", Membership) { remove(:alpha_member, @member) }
    assert_refused("Not allowed", Membership) { remove(:ward, @member) }
  end

  test "a plain member on another team can't reach the membership" do
    assert_refused("Not found", Membership) { remove(:beta_member, @member) }
  end

  test "a manager can't remove from a team they don't manage" do
    assert_refused("Not found", Membership) { remove(:alpha_manager, @beta_membership) }
  end

  test "a guardian can't remove their ward" do
    assert_refused("Not found", Membership) { remove(:guardian, membership(:ward, @alpha)) }
  end

  test "invalid and wrong-prefix IDs are not found" do
    [ "nonsense", "mbr_nonsense", @alpha.neat_id ].each do |bad|
      assert_refused("Not found", Membership) { call_tool("remove_team_member", user: user(:admin), membership_id: bad) }
    end
    assert_refused(/membership_id/, Membership) { call_tool("remove_team_member", user: user(:admin)) }
  end

  test "a read token and the setting being off refuse it" do
    assert_refused("Not allowed", Membership) { remove(:admin, @member, scopes: "mcp_read") }
    assert_refused("Writes disabled", Membership) { remove(:admin, @member, writes_enabled: false) }
  end

  test "hooks run as they do on the page" do
    assert_hook_runs("memberships - destroy") { remove(:admin, @member) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @beta_membership ],
      [ :alpha_manager, @member ],
      [ :alpha_manager, membership(:alpha_manager, @alpha) ],
      [ :alpha_manager, @beta_membership ],
      [ :alpha_member, @member ],
      [ :ward, @member ],
      [ :beta_member, @member ],
      [ :guardian, membership(:ward, @alpha) ]
    ].each do |viewer, target|
      page = page_changes_rows?(Membership, as: user(viewer)) { delete team_membership_path(target.team, target) }
      tool = changes_rows?(Membership) { remove(viewer, target) }

      assert_equal page, tool, "#{viewer} removing #{target.identifier_name}"
    end
  end
end
