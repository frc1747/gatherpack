require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::GetEventTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  def get(viewer, event)
    call_tool("get_event", user: user(viewer), event_id: event.neat_id)
  end

  test "an admin sees the event and who checked in" do
    value = get(:admin, @alpha_event).value

    assert_equal "Alpha Meeting", value["name"]
    assert_equal 2, value["checkin_count"]
    assert_equal [ "AlphaMember World", "Ward World" ], value["attendees"].map { |a| a["person"]["name"] }.sort
    assert_equal %w[checkin_id person], value["attendees"].first.keys.sort
  end

  test "a team manager sees their team's event" do
    assert_equal "Alpha Meeting", get(:alpha_manager, @alpha_event).value["name"]
  end

  test "a team-less event is for admins only" do
    assert_equal "Open Day", get(:admin, @open_event).value["name"]
    assert_equal "Not found", get(:alpha_manager, @open_event).error
  end

  test "a member of another team doesn't find the event" do
    assert_equal "Not found", get(:beta_member, @alpha_event).error
    assert_equal "Beta Meeting", get(:beta_member, @beta_event).value["name"]
  end

  test "a guardian in no team doesn't find their ward's event" do
    assert_equal "Not found", get(:guardian, @alpha_event).error
  end

  test "a wrong ID prefix is not found" do
    assert_equal "Not found", call_tool("get_event", user: user(:admin), event_id: @alpha.neat_id).error
  end

  test "check-in notes are not returned" do
    Checkin.find_by!(person: person(:alpha_member), event: @alpha_event).update_columns(notes: "private note")

    assert_not_includes get(:admin, @alpha_event).value.to_json, "private note"
  end

  test "a missing event_id is refused" do
    assert_equal "Missing required arguments: event_id", call_tool("get_event", user: user(:admin)).error
  end

  test "attendees are capped at limit, with the full count" do
    value = call_tool("get_event", user: user(:admin), event_id: @alpha_event.neat_id, limit: 1).value

    assert_equal 1, value["attendees"].size
    assert value["attendees_truncated"]
    assert_equal 2, value["checkin_count"]
    assert_not get(:admin, @alpha_event).value["attendees_truncated"]
  end

  test "a check-in limit of zero means no limit" do
    @alpha_event.update_columns(checkin_limit: 0)
    assert_nil get(:admin, @alpha_event).value["checkin_limit"]

    @alpha_event.update_columns(checkin_limit: 5)
    assert_equal 5, get(:admin, @alpha_event).value["checkin_limit"]
  end
end
