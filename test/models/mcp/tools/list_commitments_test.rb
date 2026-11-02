require "test_helper"
require_relative "../../../support/mcp_commitments_world"

class Mcp::Tools::ListCommitmentsTest < ActiveSupport::TestCase
  include McpCommitmentsWorld

  setup do
    build_mcp_world
    build_mcp_commitments_world
  end

  def titles(viewer)
    call_tool("list_commitments", user: user(viewer)).value["items"].map { |item| item["title"] }
  end

  test "an admin sees every current commitment" do
    assert_equal [ "Beta Shifts", "Shifts" ].sort, titles(:admin).sort
  end

  test "an admin's row has the team, who owes, the amount and the period" do
    item = call_tool("list_commitments", user: user(:admin)).value["items"].find { |row| row["title"] == "Shifts" }

    assert_equal({ "id" => @shifts.neat_id, "title" => "Shifts", "team" => { "id" => @alpha.neat_id, "name" => "Alpha" },
      "owing_team" => { "id" => @alpha.neat_id, "name" => "Alpha" }, "owed_each" => 2, "unit" => "shifts",
      "starts_on" => @shifts.starts_on.iso8601, "ends_on" => @shifts.ends_on.iso8601, "counts_when" => "confirmed", "organizer" => true }, item)
  end

  test "a team manager and a listed organizer see the commitment they run" do
    assert_equal [ "Shifts" ], titles(:alpha_manager)
    assert_equal [ "Shifts" ], titles(:organizer)
  end

  test "a member who owes sees it without organizer rights" do
    items = call_tool("list_commitments", user: user(:alpha_member)).value["items"]

    assert_equal [ "Shifts" ], items.map { |item| item["title"] }
    assert_not items.first["organizer"]
  end

  test "a relative in the same group sees it" do
    assert_equal [ "Shifts" ], titles(:guardian)
  end

  test "an unrelated member sees only their own team's commitment" do
    assert_equal [ "Beta Shifts" ], titles(:beta_member)
    assert_empty titles(:badge_holder) - [ "Beta Shifts" ]
  end

  test "limit truncates" do
    result = call_tool("list_commitments", user: user(:admin), limit: 1)

    assert_equal 1, result.value["items"].size
    assert result.value["truncated"]
  end

  test "it is off with the commitments feature" do
    with_feature(:commitments, false) do
      assert_equal "Feature off", call_tool("list_commitments", user: user(:admin)).error
      assert_not_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "list_commitments"
    end
  end
end
