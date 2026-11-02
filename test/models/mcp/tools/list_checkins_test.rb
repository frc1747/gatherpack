require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListCheckinsTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  def list(viewer, person_name, **args)
    call_tool("list_checkins", user: user(viewer), person_id: person(person_name).neat_id, from: "2026-03-01", to: "2026-03-31", **args)
  end

  def event_names(result)
    result.value["items"].map { |item| item["event"]["name"] }
  end

  test "an admin sees a person's check-ins, newest event first" do
    assert_equal [ "Open Day", "Alpha Meeting" ], event_names(list(:admin, :alpha_member))
  end

  test "a check-in comes with its event and time" do
    item = list(:admin, :ward).value["items"].first

    assert_equal @alpha_event.neat_id, item["event"]["id"]
    assert_equal "2026-03-10T18:00:00Z", item["event"]["start_time"]
    assert_match(/\A\d{4}-\d\d-\d\dT/, item["checked_in_at"])
  end

  test "a team manager sees check-ins at events they can see, not team-less ones" do
    assert_equal [ "Alpha Meeting" ], event_names(list(:alpha_manager, :alpha_member))
  end

  test "someone on another team doesn't find the person" do
    assert_equal "Not found", list(:beta_member, :alpha_member).error
  end

  test "a guardian in no team doesn't find their ward" do
    assert_equal "Not found", list(:guardian, :ward).error
  end

  test "a person sees their own check-ins" do
    assert_equal [ "Beta Meeting" ], event_names(list(:beta_member, :beta_member))
    assert_empty list(:guardian, :guardian).value["items"]
  end

  test "check-ins at events outside the window are left out" do
    assert_empty list(:admin, :alpha_member, from: "2026-04-01", to: "2026-04-30").value["items"]
  end

  test "limit truncates" do
    result = list(:admin, :alpha_member, limit: 1)

    assert_equal 1, result.value["items"].size
    assert result.value["truncated"]
  end

  test "windows and missing arguments are refused" do
    assert_equal "The window can be at most 366 days", list(:admin, :ward, from: "2025-01-01", to: "2026-01-03").error
    assert_equal "to can't be before from", list(:admin, :ward, from: "2026-03-31", to: "2026-03-01").error
    assert_equal "from must be a date like 2026-03-31", list(:admin, :ward, from: "x").error
    assert_equal "Missing required arguments: from, to", call_tool("list_checkins", user: user(:admin), person_id: person(:ward).neat_id).error
  end
end
