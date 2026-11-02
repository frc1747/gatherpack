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

  test "membership IDs go only to viewers who may remove the membership" do
    ids = ->(viewer) { get(viewer, @alpha).value["members"].map { |member| member["membership_id"] } }
    all = @alpha.memberships.joins(:person).order("people.last_name", "people.first_name", "memberships.id").map(&:neat_id)

    assert_equal all, ids.call(:admin)
    assert_equal all, ids.call(:alpha_manager)
    assert_equal [ nil, nil, nil ], ids.call(:alpha_member)
    assert_equal [ nil, nil, nil ], ids.call(:ward)
  end

  test "a membership ID is there exactly when remove_team_member accepts it" do
    target = Membership.find_by!(person: person(:ward), team: @alpha)
    @alpha.update!(join_permission: :has_account)

    %i[admin alpha_manager alpha_member ward beta_member guardian].each do |viewer|
      listed = get(viewer, @alpha).value["members"].find { |member| member["id"] == person(:ward).neat_id }
      removed = changes_rows?(Membership) { call_tool("remove_team_member", user: user(viewer), membership_id: target.neat_id) }

      assert_equal removed, listed&.dig("membership_id") == target.neat_id, viewer
    end
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

  test "members are limited, ordered, and flagged when truncated" do
    30.times { |i| Membership.create!(person: Person.create!(first_name: "Extra#{i}", last_name: "Zed"), team: @alpha) }
    value = get(:admin, @alpha).value

    assert_equal 25, value["members"].size
    assert_equal true, value["truncated"]
    assert_equal value["members"], get(:admin, @alpha).value["members"]
    assert_equal 33, call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id, limit: 100).value["members"].size
    assert_equal false, call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id, limit: 100).value["truncated"]
    assert_equal 2, call_tool("get_team", user: user(:admin), team_id: @alpha.neat_id, limit: 2).value["members"].size
  end

  test "a parent the viewer can't see is null" do
    hidden = create_world_team("SecretParent")
    open_child = create_world_team("Open Child", parent: hidden)
    open_child.update!(join_permission: :has_account)

    assert_nil get(:beta_member, open_child).value["parent"]
    assert_equal "SecretParent", get(:admin, open_child).value.dig("parent", "name")
  end

  test "a wrong ID prefix is not found" do
    assert_equal "Not found", call_tool("get_team", user: user(:admin), team_id: person(:admin).neat_id).error
  end
end
