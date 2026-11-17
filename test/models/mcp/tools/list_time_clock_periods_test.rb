require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListTimeClockPeriodsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
    @past = TimeClockPeriod.create!(name: "Alpha February", team: @alpha, start_time: Time.utc(2026, 2, 1), end_time: Time.utc(2026, 2, 28), permission: :added_by_manager)
    travel_to MCP_TIME_NOW
  end

  def periods(viewer, **options)
    call_tool("list_time_clock_periods", user: user(viewer), **options).value["items"]
  end

  test "an admin sees every running period, with its team, dates, permission and open punches" do
    items = periods(:admin)

    assert_equal [ "Alpha March", "Beta March", "Everyone March" ], items.map { |item| item["name"] }.sort
    alpha = items.find { |item| item["name"] == "Alpha March" }
    assert_equal @alpha_period.neat_id, alpha["id"]
    assert_equal @alpha.neat_id, alpha.dig("team", "id")
    assert_equal "added_by_admin", alpha["permission"]
    assert_equal 1, alpha["open_punches"]
    assert_equal "2026-03-01T00:00:00Z", alpha["start_time"]
    assert_nil items.find { |item| item["name"] == "Everyone March" }["team"]
  end

  test "active: false adds periods that have ended" do
    assert_includes periods(:admin, active: false).map { |item| item["id"] }, @past.neat_id
    assert_not_includes periods(:admin).map { |item| item["id"] }, @past.neat_id
  end

  test "a manager and a member see their team's periods and team-less ones" do
    assert_equal [ "Alpha March", "Everyone March" ], periods(:alpha_manager).map { |item| item["name"] }.sort
    assert_equal [ "Beta March", "Everyone March" ], periods(:beta_member).map { |item| item["name"] }.sort
  end

  test "a guardian in no team sees team-less periods only" do
    assert_equal [ "Everyone March" ], periods(:guardian).map { |item| item["name"] }
  end

  test "the open count is only what the viewer can see" do
    assert_equal 0, periods(:alpha_member).find { |item| item["name"] == "Alpha March" }["open_punches"]
    assert_equal 1, periods(:beta_member).find { |item| item["name"] == "Beta March" }["open_punches"]
  end

  test "a boolean is required, not text" do
    assert_match(/active/, call_tool("list_time_clock_periods", user: user(:admin), active: "no").error)
  end

  test "the feature being off refuses it" do
    with_feature(:time_tracking, false) { assert_equal "Feature off", call_tool("list_time_clock_periods", user: user(:admin)).error }
  end
end
