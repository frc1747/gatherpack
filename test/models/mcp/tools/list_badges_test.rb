require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListBadgesTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def items(viewer, **args)
    call_tool("list_badges", user: user(viewer), **args).value["items"].reject { |badge| badge["name"] == "MyString" } # fixture badges
  end

  test "an admin sees every badge with type, team and holder count" do
    team_badge = create_world_badge("Beta Badge", team: @beta)
    BadgeAssignment.create!(badge: team_badge, person: person(:beta_member))
    found = items(:admin)

    assert_equal [ "Beta Badge", "MCP Access" ], found.map { |badge| badge["name"] }
    assert_equal({ "id" => team_badge.neat_id, "name" => "Beta Badge", "short" => "Bet", "badge_type" => badge_types(:one).name,
      "team" => { "id" => @beta.neat_id, "name" => "Beta" }, "holder_count" => 1 }, found.first)
    assert_nil found.last["team"]
  end

  test "a team manager sees team-less badges and their own teams' badges" do
    create_world_badge("Alpha Badge", team: @alpha)
    create_world_badge("Beta Badge", team: @beta)

    assert_equal [ "Alpha Badge", "MCP Access" ], items(:alpha_manager).map { |badge| badge["name"] }
  end

  test "a member on another team doesn't see badges of teams they aren't in" do
    create_world_badge("Alpha Badge", team: @alpha)

    assert_equal [ "MCP Access" ], items(:beta_member).map { |badge| badge["name"] }
  end

  test "a guardian in no team sees only team-less badges" do
    create_world_badge("Alpha Badge", team: @alpha)

    assert_equal [ "MCP Access" ], items(:guardian).map { |badge| badge["name"] }
  end

  test "the holder count only includes holders the viewer can see" do
    assert_equal [ 1 ], items(:admin).map { |badge| badge["holder_count"] }
    assert_equal [ 1 ], items(:beta_member).map { |badge| badge["holder_count"] }
    assert_equal [ 0 ], items(:alpha_member).map { |badge| badge["holder_count"] }
  end

  test "it is off with the badges feature" do
    with_feature(:badges, false) do
      assert_equal "Feature off", call_tool("list_badges", user: user(:admin)).error
    end
  end

  test "limit truncates" do
    create_world_badge("Another")
    result = call_tool("list_badges", user: user(:admin), limit: 1)

    assert_equal [ "Another" ], result.value["items"].map { |badge| badge["name"] }
    assert_equal true, result.value["truncated"]
  end
end
