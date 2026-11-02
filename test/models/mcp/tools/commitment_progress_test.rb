require "test_helper"
require_relative "../../../support/mcp_commitments_world"

class Mcp::Tools::CommitmentProgressTest < ActiveSupport::TestCase
  include McpCommitmentsWorld

  setup do
    build_mcp_world
    build_mcp_commitments_world
  end

  def progress(viewer, commitment = @shifts, **arguments)
    call_tool("commitment_progress", user: user(viewer), commitment_id: commitment.neat_id, **arguments)
  end

  def rows(viewer, commitment = @shifts, **arguments)
    progress(viewer, commitment, **arguments).value["rows"]
  end

  def names(row)
    row["people"].map { |p| p["name"] }
  end

  test "an admin, a team manager and a listed organizer get a row for each group" do
    [ :admin, :alpha_manager, :organizer ].each do |viewer|
      table = rows(viewer)

      assert_equal 4, table.sum { |row| row["people"].size }, viewer
      assert_includes table.flat_map { |row| names(row) }, "Ward World"
    end
  end

  test "a row has owed, confirmed, planned and remaining" do
    row = rows(:admin).find { |r| names(r) == [ "AlphaMember World" ] }

    assert_equal 2, row["owed"]
    assert_equal 1, row["confirmed"]
    assert_equal 0, row["planned"]
    assert_equal 1, row["remaining"]
    assert_not row["met"]
    assert_equal [ true, 1, 0 ], row["sources"].map { |line| [ line["available"], line["confirmed"], line["planned"] ] }.first
    assert_nil row["credits"]
  end

  test "a grouped commitment pools the group's credit and counts the relative" do
    row = rows(:admin).find { |r| names(r) == [ "Ward World" ] }

    assert_equal 2, row["owed"]
    assert_equal 1, row["planned"]
  end

  test "an organizer asking for one person gets the credits and where each came from" do
    row = rows(:organizer, person_id: person(:alpha_member).neat_id).sole

    assert_equal [ "AlphaMember World" ], names(row)
    assert_equal [ [ "Checked in: Past Shift", true, "AlphaMember World" ] ],
      row["credits"].map { |credit| [ credit["label"], credit["confirmed"], credit["person"]["name"] ] }
  end

  test "a member who owes sees only their own row" do
    result = rows(:alpha_member)

    assert_equal 1, result.size
    assert_equal [ "AlphaMember World" ], names(result.first)
    assert_equal 1, result.first["credits"].size
  end

  test "a member can't ask for another member" do
    assert_equal "Not found", progress(:alpha_member, person_id: person(:ward).neat_id).error
    assert_equal "Not found", progress(:ward, person_id: person(:alpha_member).neat_id).error
  end

  test "a relative in the group sees the group's progress and may ask for the member" do
    result = rows(:guardian)

    assert_equal [ [ "Ward World" ] ], result.map { |row| names(row) }
    assert_equal 1, rows(:guardian, person_id: person(:ward).neat_id).size
    assert_equal "Not found", progress(:guardian, person_id: person(:alpha_member).neat_id).error
  end

  test "an unrelated member can't see the commitment" do
    assert_equal "Not found", progress(:beta_member).error
    assert_equal "Not found", progress(:beta_member, person_id: person(:alpha_member).neat_id).error
  end

  test "a person who doesn't owe the commitment is not found, even for an admin" do
    assert_equal "Not found", progress(:admin, person_id: person(:beta_member).neat_id).error
    assert_equal "Not found", progress(:admin, person_id: "per_nope").error
  end

  test "a commitment that isn't there is not found" do
    assert_equal "Not found", call_tool("commitment_progress", user: user(:admin), commitment_id: "cmt_nope").error
  end

  test "limit truncates the rows" do
    result = progress(:admin, limit: 1).value

    assert_equal 1, result["rows"].size
    assert result["truncated"]
  end

  test "it is off with the commitments feature" do
    with_feature(:commitments, false) do
      assert_equal "Feature off", progress(:admin).error
      assert_not_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "commitment_progress"
    end
  end
end
