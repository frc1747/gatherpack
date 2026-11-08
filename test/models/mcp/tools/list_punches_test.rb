require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ListPunchesTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
    travel_to MCP_TIME_NOW
  end

  def punches(viewer, from: "2026-03-01", to: "2026-03-31", **options)
    call_tool("list_punches", user: user(viewer), from: from, to: to, **options)
  end

  def people_in(result)
    result.value["items"].map { |item| item.dig("person", "name") }.uniq.sort
  end

  test "an admin sees everyone's, newest first, with person, period, times and hours" do
    items = punches(:admin).value["items"]

    assert_equal 6, items.size
    assert_equal items.map { |item| item["start_time"] }.sort.reverse, items.map { |item| item["start_time"] }
    closed = items.find { |item| item.dig("person", "id") == person(:ward).neat_id }
    assert_equal @alpha_period.neat_id, closed.dig("period", "id")
    assert_equal 1.0, closed["hours"]
    assert_equal "2026-03-10T09:00:00Z", closed["start_time"]
    assert_equal "2026-03-10T10:00:00Z", closed["end_time"]
    open = items.find { |item| item["id"] == @open_punch.neat_id }
    assert_nil open["end_time"]
    assert_nil open["hours"]
    assert_equal [ "still_clocked_in" ], open["flags"]
  end

  test "a manager sees their teams' people and themselves; a member and a guardian only their own" do
    assert_equal [ "AlphaManager World", "AlphaMember World", "Ward World" ], people_in(punches(:alpha_manager))
    assert_equal [ "BetaMember World" ], people_in(punches(:beta_member))
    assert_empty punches(:guardian).value["items"]
    assert_empty punches(:guardian, person_id: person(:guardian).neat_id).value["items"]
  end

  test "filters take what the viewer can see, and nothing else" do
    assert_equal [ "Ward World" ], people_in(punches(:admin, person_id: person(:ward).neat_id))
    assert_equal [ "BetaMember World" ], people_in(punches(:admin, period_id: @beta_period.neat_id))
    assert_equal "Not found", punches(:alpha_manager, person_id: person(:beta_member).neat_id).error
    assert_equal "Not found", punches(:alpha_manager, period_id: @beta_period.neat_id).error
    assert_equal "Not found", punches(:guardian, person_id: person(:ward).neat_id).error
    assert_empty punches(:alpha_member, person_id: person(:ward).neat_id).value["items"]
  end

  test "flagged needs flagged? and returns the page's three groups" do
    long = create_world_punch(person(:ward), @alpha_period, 100, 120)
    overlap = create_world_punch(person(:alpha_member), @alpha_period, 10, 13)

    items = punches(:alpha_manager, flagged: true).value["items"]
    by_id = items.to_h { |item| [ item["id"], item["flags"] ] }

    assert_equal [ "too_long" ], by_id[long.neat_id]
    assert_equal [ "near_duplicate" ], by_id[overlap.neat_id]
    assert_equal [ "still_clocked_in" ], by_id[@open_punch.neat_id] - [ "near_duplicate" ]
    assert_equal 4, items.size
    assert_equal "Not allowed", punches(:beta_member, flagged: true).error
    assert_equal "Not allowed", punches(:guardian, flagged: true).error
    assert_equal 2, punches(:beta_member, flagged: false).value["items"].size
  end

  test "someone who can't open the flagged page gets null flags, not an empty list" do
    punches(:beta_member).value["items"].each { |item| assert_nil item["flags"] }
  end

  test "a note goes only to those who could open the edit form" do
    noted = TimeClockPunch.create!(person: person(:beta_member), time_clock_period: @beta_period, start_time: Time.utc(2026, 3, 5, 9), end_time: Time.utc(2026, 3, 5, 10), note: "Left early", created_by: "kiosk")

    assert_equal "Left early", punches(:admin).value["items"].find { |item| item["id"] == noted.neat_id }["note"]
    assert_nil punches(:beta_member).value["items"].find { |item| item["id"] == noted.neat_id }["note"]
  end

  test "a manager on a period they can edit, and a member on their own punch in no period, get the note" do
    managed_period = TimeClockPeriod.create!(name: "Alpha Managers", team: @alpha, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: :added_by_manager)
    managed = TimeClockPunch.create!(person: person(:ward), time_clock_period: managed_period, start_time: Time.utc(2026, 3, 5, 9), note: "Managed note", created_by: "kiosk")
    own = TimeClockPunch.create!(person: person(:beta_member), start_time: Time.utc(2026, 3, 5, 9), note: "Own note")

    assert_equal "Managed note", punches(:alpha_manager).value["items"].find { |item| item["id"] == managed.neat_id }["note"]
    assert_equal "Own note", punches(:beta_member).value["items"].find { |item| item["id"] == own.neat_id }["note"]
  end

  test "the window is inclusive, at most 366 days, and must be real dates" do
    assert_equal 6, punches(:admin, from: "2026-03-10", to: "2026-03-11").value["items"].size
    assert_empty punches(:admin, from: "2026-03-12", to: "2026-03-12").value["items"]
    assert_equal "The window can be at most 366 days", punches(:admin, from: "2025-01-01", to: "2026-03-31").error
    assert_nil punches(:admin, from: "2025-01-01", to: "2026-01-01").error
    assert_equal "to can't be before from", punches(:admin, from: "2026-03-02", to: "2026-03-01").error
    assert_equal "from must be a date like 2026-03-31", punches(:admin, from: "2026-13-01").error
    assert_match(/to/, call_tool("list_punches", user: user(:admin), from: "2026-03-01").error)
  end

  test "a limit truncates, and a boolean is required for flagged" do
    result = punches(:admin, limit: 2)

    assert_equal 2, result.value["items"].size
    assert_equal true, result.value["truncated"]
    assert_match(/flagged/, punches(:admin, flagged: "no").error)
  end
end
