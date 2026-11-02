require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListEventsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  def list(viewer, **args)
    call_tool("list_events", user: user(viewer), from: "2026-03-01", to: "2026-03-31", **args)
  end

  def names(result)
    result.value["items"].map { |item| item["name"] }
  end

  test "an admin sees every event in the window, oldest first" do
    assert_equal [ "Alpha Meeting", "Beta Meeting", "Open Day" ], names(list(:admin))
  end

  test "events come with team, type, times and check-in count" do
    item = list(:admin).value["items"].first

    assert_equal({ "id" => @alpha_event.neat_id, "name" => "Alpha Meeting", "team" => { "id" => @alpha.neat_id, "name" => "Alpha" },
      "event_type" => { "id" => event_types(:one).neat_id, "name" => event_types(:one).name.to_s },
      "start_time" => "2026-03-10T18:00:00Z", "end_time" => "2026-03-10T19:00:00Z", "location" => nil, "checkin_count" => 2 }, item)
  end

  test "a team without a manager role sees only their team's events, not team-less ones" do
    assert_equal [ "Alpha Meeting" ], names(list(:alpha_manager))
    assert_equal [ "Beta Meeting" ], names(list(:beta_member))
  end

  test "a guardian in no team sees no events" do
    assert_empty list(:guardian).value["items"]
  end

  test "only events starting in the window are listed" do
    assert_equal [ "Beta Meeting" ], names(call_tool("list_events", user: user(:admin), from: "2026-03-11", to: "2026-03-11"))
  end

  test "team filter" do
    assert_equal [ "Beta Meeting" ], names(list(:admin, team_id: @beta.neat_id))
  end

  test "a team outside the viewer's scope is not found" do
    @alpha.update!(join_permission: :added_by_admin)

    assert_equal "Not found", list(:beta_member, team_id: @alpha.neat_id).error
  end

  test "a visible team doesn't reveal events the viewer can't see" do
    @alpha.update!(join_permission: :has_account)

    assert_empty list(:beta_member, team_id: @alpha.neat_id).value["items"]
  end

  test "event type filter" do
    assert_equal [ "Alpha Meeting", "Beta Meeting", "Open Day" ], names(list(:admin, event_type_id: event_types(:one).neat_id))
    assert_empty names(list(:admin, event_type_id: event_types(:two).neat_id))
    assert_equal "Not found", list(:admin, event_type_id: @alpha.neat_id).error
  end

  test "limit truncates" do
    result = list(:admin, limit: 2)

    assert_equal 2, result.value["items"].size
    assert result.value["truncated"]
  end

  test "a window of more than 366 days is refused" do
    assert_equal "The window can be at most 366 days", call_tool("list_events", user: user(:admin), from: "2025-01-01", to: "2026-01-03").error
    assert_not call_tool("list_events", user: user(:admin), from: "2025-01-01", to: "2026-01-02").error?
  end

  test "bad dates and a reversed window are refused" do
    assert_equal "from must be a date like 2026-03-31", call_tool("list_events", user: user(:admin), from: "March", to: "2026-03-31").error
    assert_equal "to can't be before from", call_tool("list_events", user: user(:admin), from: "2026-03-31", to: "2026-03-01").error
  end

  test "missing arguments are refused" do
    assert_equal "Missing required arguments: to", call_tool("list_events", user: user(:admin), from: "2026-03-01").error
  end

  test "it is off with the events feature" do
    with_feature(:events, false) { assert_equal "Feature off", list(:admin).error }
  end
end
