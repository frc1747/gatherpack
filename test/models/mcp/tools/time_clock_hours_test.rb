require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::TimeClockHoursTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  setup { travel_to MCP_TIME_NOW }
  teardown { travel_back }

  def hours(viewer, **args)
    call_tool("time_clock_hours", user: user(viewer), from: "2026-03-01", to: "2026-03-31", **args)
  end

  def by_name(result)
    result.value["items"].to_h { |item| [ item["person"]["name"].split.first, item ] }
  end

  test "an admin sees a team's hours per person, open punches counted to now" do
    items = by_name(hours(:admin, team_id: @alpha.neat_id))

    assert_equal %w[AlphaManager AlphaMember Ward], items.keys
    assert_equal({ "hours" => 2.0, "open_hours" => 0.0, "clocked_in" => false, "punches" => 1 }, items["AlphaMember"].except("person"))
    assert_equal({ "hours" => 31.0, "open_hours" => 28.0, "clocked_in" => true, "punches" => 2 }, items["AlphaManager"].except("person"))
  end

  test "an admin can ask for one person" do
    item = hours(:admin, person_id: person(:beta_member).neat_id).value["items"].sole

    assert_equal 31.0, item["hours"]
    assert item["clocked_in"]
  end

  test "a team manager sees their team" do
    assert_equal %w[AlphaManager AlphaMember Ward], by_name(hours(:alpha_manager, team_id: @alpha.neat_id)).keys
  end

  test "a plain member sees only their own punches" do
    items = by_name(hours(:alpha_member, team_id: @alpha.neat_id))

    assert_equal [ "AlphaMember" ], items.keys
  end

  test "a member of another team gets nothing for a team they can see but aren't in" do
    @alpha.update!(join_permission: :has_account)

    assert_empty hours(:beta_member, team_id: @alpha.neat_id).value["items"]
  end

  test "a team outside the viewer's scope is not found" do
    @alpha.update!(join_permission: :added_by_admin)

    assert_equal "Not found", hours(:beta_member, team_id: @alpha.neat_id).error
  end

  test "someone on another team doesn't find the person" do
    assert_equal "Not found", hours(:alpha_manager, person_id: person(:beta_member).neat_id).error
  end

  test "a guardian in no team doesn't find their ward but sees themselves" do
    assert_equal "Not found", hours(:guardian, person_id: person(:ward).neat_id).error
    assert_empty hours(:guardian, person_id: person(:guardian).neat_id).value["items"]
  end

  test "punches outside any period are left out" do
    TimeClockPunch.create!(person: person(:alpha_member), start_time: Time.utc(2026, 3, 10, 14), end_time: Time.utc(2026, 3, 10, 19), created_by: "kiosk")

    assert_equal 2.0, hours(:admin, person_id: person(:alpha_member).neat_id).value["items"].sole["hours"]
  end

  test "only punches starting in the window count" do
    result = hours(:admin, team_id: @alpha.neat_id, from: "2026-03-11", to: "2026-03-11")

    assert_equal %w[AlphaManager], by_name(result).keys
    assert_equal 28.0, result.value["items"].sole["hours"]
  end

  test "one of person_id and team_id is required" do
    assert_equal "Give person_id or team_id", hours(:admin).error
    assert_equal "Give person_id or team_id, not both", hours(:admin, person_id: person(:ward).neat_id, team_id: @alpha.neat_id).error
  end

  test "windows and missing arguments are refused" do
    assert_equal "The window can be at most 366 days", hours(:admin, team_id: @alpha.neat_id, from: "2025-01-01", to: "2026-01-03").error
    assert_equal "to can't be before from", hours(:admin, team_id: @alpha.neat_id, from: "2026-03-31", to: "2026-03-01").error
    assert_equal "Missing required arguments: to", call_tool("time_clock_hours", user: user(:admin), team_id: @alpha.neat_id, from: "2026-03-01").error
  end

  test "it is off with time tracking" do
    with_feature(:time_tracking, false) { assert_equal "Feature off", hours(:admin, team_id: @alpha.neat_id).error }
  end
end
