require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetTeamTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def get(viewer, team)
    call_tool("get_team", user: user(viewer), team_id: team.neat_id)
  end

  def member_names(result)
    result.value["members"].map { |member| member["name"].split.first }
  end

  test "an admin sees the team, its managers, members and sub-teams" do
    child = create_world_team("Alpha Child", parent: @alpha)
    @alpha.update!(description: "The A team")
    value = get(:admin, @alpha).value

    assert_equal [ @alpha.neat_id, "Alpha", "The A team", team_types(:one).name, nil ], value.values_at("id", "name", "description", "team_type", "parent")
    assert_equal [ { "id" => child.neat_id, "name" => "Alpha Child" } ], value["children"]
    assert_equal [ { "id" => person(:alpha_manager).neat_id, "name" => "AlphaManager World" } ], value["managers"]
    assert_equal [ [ "AlphaManager", true ], [ "AlphaMember", false ], [ "Ward", false ] ],
      value["members"].map { |member| [ member["name"].split.first, member["manager"] ] }
  end

  test "a sub-team shows its parent" do
    child = create_world_team("Alpha Child", parent: @alpha)

    assert_equal({ "id" => @alpha.neat_id, "name" => "Alpha" }, get(:admin, child).value["parent"])
  end

  test "a manager sees their team" do
    assert_equal %w[AlphaManager AlphaMember Ward], member_names(get(:alpha_manager, @alpha))
  end

  test "a member sees their own team and not a team limited to admins" do
    assert_equal %w[AlphaManager AlphaMember Ward], member_names(get(:alpha_member, @alpha))
    assert_equal "Not found", get(:alpha_member, @beta).error
  end

  test "a guardian in no team can't find a team that isn't open" do
    assert_equal "Not found", get(:guardian, @alpha).error
  end

  test "an open team shows its description and managers but only the members the viewer can see" do
    @beta.update!(join_permission: :has_account, description: "Open to all")
    @beta.memberships.find_by!(person: person(:beta_member)).update!(manager: true)
    value = get(:alpha_member, @beta).value

    assert_equal "Open to all", value["description"]
    assert_equal [ "BetaMember World" ], value["managers"].map { |manager| manager["name"] }
    assert_empty value["members"]
  end

  test "sub-teams the viewer can't see are left out" do
    create_world_team("Hidden Child", parent: @alpha)
    create_world_team("Open Child", parent: @alpha).update!(join_permission: :has_account)

    assert_equal [ "Hidden Child", "Open Child" ], get(:alpha_manager, @alpha).value["children"].map { |child| child["name"] }
    assert_equal [ "Open Child" ], get(:alpha_member, @alpha).value["children"].map { |child| child["name"] }
  end

  test "a wrong ID prefix is not found" do
    assert_equal "Not found", call_tool("get_team", user: user(:admin), team_id: person(:admin).neat_id).error
  end
end
