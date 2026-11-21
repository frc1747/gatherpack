require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListTeamsTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  # Without the fixtures' own teams.
  def items(result)
    result.value["items"].reject { |team| [ "Alpha Team", "Beta Team" ].include?(team["name"]) }
  end

  test "an admin sees every team with its type, parent and member count" do
    child = create_world_team("Alpha Child", parent: @alpha)
    Membership.create!(person: person(:alpha_member), team: child)
    result = call_tool("list_teams", user: user(:admin))

    assert_equal [ "Alpha", "Alpha Child", "Beta" ], items(result).map { |team| team["name"] }
    assert_equal({ "id" => child.neat_id, "name" => "Alpha Child", "team_type" => team_types(:one).name,
      "parent" => { "id" => @alpha.neat_id, "name" => "Alpha" }, "member_count" => 1 }, items(result)[1])
    assert_equal [ 3, 1, 2 ], items(result).map { |team| team["member_count"] }
    assert_equal false, result.value["truncated"]
  end

  test "a manager sees their team and the sub-teams under it" do
    create_world_team("Alpha Child", parent: @alpha)

    assert_equal [ "Alpha", "Alpha Child" ], items(call_tool("list_teams", user: user(:alpha_manager))).map { |team| team["name"] }
  end

  test "a member on another team sees their own team only, and not a team limited to admins" do
    assert_equal [ "Beta" ], items(call_tool("list_teams", user: user(:beta_member))).map { |team| team["name"] }
  end

  test "an open team is listed but its member count only includes people the viewer can see" do
    @beta.update!(join_permission: :has_account)
    found = items(call_tool("list_teams", user: user(:alpha_member))).find { |team| team["name"] == "Beta" }

    assert_equal 0, found["member_count"]
  end

  test "a guardian in no team sees only open teams" do
    @beta.update!(join_permission: :requires_approval)

    assert_equal [ "Beta" ], items(call_tool("list_teams", user: user(:guardian))).map { |team| team["name"] }
  end

  test "parent_id narrows to the direct sub-teams" do
    child = create_world_team("Alpha Child", parent: @alpha)
    create_world_team("Alpha Grandchild", parent: child)

    assert_equal [ "Alpha Child" ], items(call_tool("list_teams", user: user(:admin), parent_id: @alpha.neat_id)).map { |team| team["name"] }
  end

  test "a parent outside the viewer's scope or with a wrong prefix is not found" do
    assert_equal "Not found", call_tool("list_teams", user: user(:beta_member), parent_id: @alpha.neat_id).error
    assert_equal "Not found", call_tool("list_teams", user: user(:admin), parent_id: person(:admin).neat_id).error
  end

  test "a parent the viewer can't see is null" do
    hidden = create_world_team("SecretParent")
    create_world_team("Open Child", parent: hidden).update!(join_permission: :has_account)
    found = ->(viewer) { items(call_tool("list_teams", user: user(viewer))).find { |team| team["name"] == "Open Child" } }

    assert_nil found.call(:beta_member)["parent"]
    assert_nil found.call(:guardian)["parent"]
    assert_equal "SecretParent", found.call(:admin).dig("parent", "name")
  end

  test "limit truncates" do
    result = call_tool("list_teams", user: user(:admin), limit: 1)

    assert_equal [ "Alpha" ], items(result).map { |team| team["name"] }
    assert_equal true, result.value["truncated"]
  end
end
