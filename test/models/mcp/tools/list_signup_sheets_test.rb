require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_signups_world"

class Mcp::Tools::ListSignupSheetsTest < ActiveSupport::TestCase
  include McpWorld
  include McpSignupsWorld

  setup do
    build_mcp_world
    build_mcp_signups_world
    travel_to MCP_SIGNUPS_NOW
  end

  def list(viewer, **args)
    call_tool("list_signup_sheets", user: user(viewer), **args)
  end

  def titles(result)
    result.value["items"].map { |item| item["title"] }
  end

  test "an admin sees every sheet that isn't archived, by title" do
    assert_equal [ "Bake Sale", "Beta Sale", "Closed Sale", "Draft Sale", "Quiet Sale" ], titles(list(:admin))
  end

  test "a sheet comes with team, next event and its counts" do
    item = list(:admin).value["items"].first

    assert_equal({ "id" => @sheet.neat_id, "title" => "Bake Sale", "status" => "open", "team" => { "id" => @alpha.neat_id, "name" => "Alpha" },
      "organizer" => true,
      "next_event" => { "id" => @bake_day.neat_id, "name" => "Bake Day", "start_time" => "2026-03-14T10:00:00Z",
        "end_time" => "2026-03-14T12:00:00Z", "location" => nil, "time_unset" => false },
      "filled" => 4, "open" => 10, "unlimited_slots" => 0 }, item)
  end

  test "a window limits the events counted and the sheets listed" do
    item = list(:admin, from: "2026-03-15", to: "2026-03-15").value["items"].first

    assert_equal [ "Bake Sale" ], titles(list(:admin, from: "2026-03-15", to: "2026-03-15"))
    assert_equal "Clean-up", item["next_event"]["name"]
    assert_equal 0, item["filled"]
    assert_equal 7, item["open"]
  end

  test "without a window every sheet the index lists is there, with no next event where nothing is upcoming" do
    @bake_day.update!(start_time: Time.utc(2026, 3, 1, 10), end_time: Time.utc(2026, 3, 1, 12))
    @cleanup.update!(start_time: Time.utc(2026, 3, 2, 10), end_time: Time.utc(2026, 3, 2, 12))
    empty = create_signups_sheet("No Dates", @alpha, [])
    items = list(:admin).value["items"]

    assert_equal [ "Bake Sale", "Beta Sale", "Closed Sale", "Draft Sale", "No Dates", "Quiet Sale" ], items.map { |item| item["title"] }
    assert_equal [ nil, 0, 0, 0 ], items.find { |item| item["id"] == empty.neat_id }.values_at("next_event", "filled", "open", "unlimited_slots")
    assert_nil items.find { |item| item["title"] == "Bake Sale" }["next_event"]
    assert_not_includes titles(list(:admin, from: "2026-01-01", to: "2026-12-31")), "No Dates"
  end

  test "the default window leaves out events that have started, and a window starts at its day" do
    assert_equal [ "Bake Day" ], list(:admin).value["items"].select { |item| item["id"] == @sheet.neat_id }.map { |item| item["next_event"]["name"] }
    travel_to Time.utc(2026, 3, 14, 11, 0)
    assert_equal "Clean-up", list(:admin).value["items"].find { |item| item["id"] == @sheet.neat_id }["next_event"]["name"]
    assert_equal "Bake Day", list(:admin, from: "2026-03-14").value["items"].find { |item| item["id"] == @sheet.neat_id }["next_event"]["name"]
    assert_equal "Past Sale", list(:admin, from: "2026-03-10", to: "2026-03-10").value["items"].first["next_event"]["name"]
  end

  test "an event with no time set is upcoming all day and flagged" do
    day = create_signups_event("Date Only", @alpha, Time.utc(2026, 3, 12, 0, 0))
    day.update!(end_time: Time.utc(2026, 3, 12, 23, 59))
    sheet = create_signups_sheet("Day Sale", @alpha, [ day ])
    item = list(:admin).value["items"].find { |i| i["id"] == sheet.neat_id }

    assert_equal [ "Date Only", true ], item["next_event"].values_at("name", "time_unset")
    assert_equal false, list(:admin).value["items"].find { |i| i["id"] == @sheet.neat_id }["next_event"]["time_unset"]
  end

  test "the window follows the app's time zone, not UTC" do
    with_settings(time_zone: "America/Detroit") do
      late = create_signups_event("Late Show", @alpha, Time.utc(2026, 3, 15, 3, 30))
      create_signups_sheet("Evening Sale", @alpha, [ late ])

      assert_includes titles(list(:admin, from: "2026-03-14", to: "2026-03-14")), "Evening Sale"
      assert_empty titles(list(:admin, from: "2026-03-15", to: "2026-03-15")).grep(/Evening/)
    end
  end

  test "a limit truncates, in title order" do
    result = list(:admin, limit: 2)

    assert_equal [ "Bake Sale", "Beta Sale" ], titles(result)
    assert result.value["truncated"]
    assert_not list(:admin).value["truncated"]
  end

  test "slots turned off are not counted" do
    @bake_day_cashier.signup_slot.update!(disabled: true)
    item = list(:admin).value["items"].find { |i| i["id"] == @sheet.neat_id }

    assert_equal [ 2, 10 ], item.values_at("filled", "open")
  end

  test "dates must be YYYY-MM-DD" do
    assert_match(/from must be a date/, list(:admin, from: "2026-03").error)
    assert_match(/to must be a date/, list(:admin, to: "03/15/2026").error)
  end

  test "a slot with no cap counts as unlimited" do
    assert_equal 1, list(:admin).value["items"].find { |item| item["title"] == "Quiet Sale" }["unlimited_slots"]
  end

  test "a team manager runs their team's sheets, drafts and closed ones included" do
    assert_equal [ "Bake Sale", "Closed Sale", "Draft Sale", "Quiet Sale" ], titles(list(:alpha_manager))
  end

  test "a sheet organizer sees the sheets they run among the open ones, not other drafts or closed sheets" do
    items = list(:organizer).value["items"]

    assert_equal [ "Bake Sale", "Quiet Sale" ], items.map { |item| item["title"] }
    assert_equal [ true, false ], items.map { |item| item["organizer"] }
  end

  test "an audience member sees open sheets only, not drafts or closed ones" do
    result = list(:alpha_member)

    assert_equal [ "Bake Sale", "Quiet Sale" ], titles(result)
    assert result.value["items"].none? { |item| item["organizer"] }
  end

  test "someone outside the audience doesn't see the sheet" do
    assert_equal [ "Beta Sale" ], titles(list(:beta_member))
  end

  test "a relative sees only the sheet they could sign up a family member for" do
    assert_equal [ "Bake Sale" ], titles(list(:guardian))
  end

  test "an invalid date is refused" do
    assert_match(/from must be a date/, list(:admin, from: "soon").error)
    assert_match(/before from/, list(:admin, from: "2026-03-15", to: "2026-03-14").error)
  end

  test "feature off means the tool is neither listed nor callable" do
    with_feature(:signups, false) do
      refute_includes Mcp.available_tools(mcp_context(user(:admin))).map(&:tool_name), "list_signup_sheets"
      assert_equal "Feature off", list(:admin).error
    end
  end
end
