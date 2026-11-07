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
      "owing_team" => { "id" => @alpha.neat_id, "name" => "Alpha" }, "base_amount" => 2, "additional_amount" => 1,
      "grouped" => true, "owing_badge" => nil, "exempt_badge" => nil, "unit" => "shifts",
      "starts_on" => @shifts.starts_on.iso8601, "ends_on" => @shifts.ends_on.iso8601, "counts_when" => "confirmed", "organizer" => true }, item)
  end

  test "badge limits are stated" do
    limit = badge_for("Limit", person(:alpha_member))
    exempt = badge_for("Exempt", person(:ward))
    commitment = Commitment.create!(title: "Limited", team: @alpha, owing_team: @alpha, owing_badge: limit, exempt_badge: exempt, base_amount: 5,
      unit: "shifts", starts_on: Date.current, ends_on: 1.month.from_now.to_date)
    item = call_tool("list_commitments", user: user(:alpha_manager)).value["items"].find { |row| row["id"] == commitment.neat_id }

    assert_equal({ "id" => limit.neat_id, "name" => "Limit" }, item["owing_badge"])
    assert_equal({ "id" => exempt.neat_id, "name" => "Exempt" }, item["exempt_badge"])
    assert_equal [ 5, 0, false ], item.values_at("base_amount", "additional_amount", "grouped")
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

  private

  def badge_for(name, holder)
    create_world_badge(name).tap { |badge| BadgeAssignment.create!(badge: badge, person: holder) }
  end

  test "the four commitment tools say they are superseded by the checklist tools" do
    replacements = { "list_commitments" => "list_checklists", "commitment_progress" => "checklist_status",
      "add_commitment_adjustment" => "add_credit_adjustment", "remove_commitment_adjustment" => "remove_credit_adjustment" }
    replacements.each do |name, replacement|
      tool = Mcp.tool(name)
      assert_includes tool.description, "Superseded by #{replacement}", name
    end
  end
end
