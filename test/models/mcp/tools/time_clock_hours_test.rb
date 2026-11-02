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
    assert_equal({ "hours" => 2.0, "open_hours" => 0.0, "open_in_window" => false, "punches" => 1 }, items["AlphaMember"].except("person"))
    assert_equal({ "hours" => 31.0, "open_hours" => 28.0, "open_in_window" => true, "punches" => 2 }, items["AlphaManager"].except("person"))
  end

  test "an admin can ask for one person" do
    item = hours(:admin, person_id: person(:beta_member).neat_id).value["items"].sole

    assert_equal 31.0, item["hours"]
    assert item["open_in_window"]
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

  test "the team filter doesn't list the roster of a team whose page shows no members" do
    child = create_world_team("Alpha Juniors", parent: @alpha)
    @alpha.update!(join_permission: :has_account)
    Membership.find_by!(person: person(:beta_member), team: @beta).update!(manager: true)
    Membership.create!(person: person(:alpha_manager), team: @beta)
    Membership.create!(person: person(:beta_member), team: child)

    names = ->(viewer) { by_name(hours(viewer, team_id: @alpha.neat_id)).keys.sort }

    assert_equal %w[AlphaManager AlphaMember BetaMember Ward], names.call(:admin)
    assert_equal %w[AlphaManager AlphaMember BetaMember Ward], names.call(:alpha_manager)
    assert_equal %w[BetaMember], names.call(:beta_member), "a manager who isn't on Alpha's full page"
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
    assert_equal 16.0, result.value["items"].sole["hours"]
  end

  test "one of person_id and team_id is required" do
    assert_equal "Give person_id or team_id", hours(:admin).error
    assert_equal "Give person_id or team_id, not both", hours(:admin, person_id: person(:ward).neat_id, team_id: @alpha.neat_id).error
  end

  test "windows and missing arguments are refused" do
    assert_equal "The window can be at most 366 days", hours(:admin, team_id: @alpha.neat_id, from: "2025-01-01", to: "2026-01-02").error
    assert_equal "to can't be before from", hours(:admin, team_id: @alpha.neat_id, from: "2026-03-31", to: "2026-03-01").error
    assert_equal "Missing required arguments: to", call_tool("time_clock_hours", user: user(:admin), team_id: @alpha.neat_id, from: "2026-03-01").error
  end

  test "it is off with time tracking" do
    with_feature(:time_tracking, false) { assert_equal "Feature off", hours(:admin, team_id: @alpha.neat_id).error }
  end

  test "an open punch is counted only to the end of the window" do
    create_world_punch(person(:alpha_member), @alpha_period, 20, nil)
    item = hours(:admin, person_id: person(:alpha_member).neat_id, from: "2026-03-10", to: "2026-03-10").value["items"].sole

    assert_equal 6.0, item["hours"]
    assert_equal 4.0, item["open_hours"]
    assert item["open_in_window"]
  end

  test "an open punch that hasn't started is not counted or flagged" do
    create_world_punch(person(:alpha_member), @alpha_period, 24 * 20, nil)
    item = hours(:admin, person_id: person(:alpha_member).neat_id).value["items"].sole

    assert_equal({ "hours" => 2.0, "open_hours" => 0.0, "open_in_window" => false, "punches" => 1 }, item.except("person"))
  end

  test "a person in two teams shows only the hours in periods the viewer can see" do
    Membership.create!(person: person(:alpha_member), team: @beta)
    create_world_punch(person(:alpha_member), @beta_period, 14, 19)

    assert_equal 2.0, hours(:alpha_manager, person_id: person(:alpha_member).neat_id).value["items"].sole["hours"]
    assert_equal 7.0, hours(:admin, person_id: person(:alpha_member).neat_id).value["items"].sole["hours"]
  end

  test "a team filter includes members of its sub-teams" do
    child = Team.create!(name: "Alpha Juniors", team_type: team_types(:one), parent: @alpha)
    junior = create_world_person("Junior", child)
    create_world_punch(junior, @everyone_period, 9, 10)

    assert_includes by_name(hours(:admin, team_id: @alpha.neat_id)).keys, "Junior"
  end

  test "a punch near midnight lands on its local day" do
    TimeClockPunch.create!(person: person(:ward), time_clock_period: @alpha_period, created_by: "kiosk",
      start_time: Time.utc(2026, 3, 11, 3, 30), end_time: Time.utc(2026, 3, 11, 4, 30))
    with_settings(time_zone: "America/Detroit") do
      assert_equal 2.0, hours(:admin, person_id: person(:ward).neat_id, from: "2026-03-10", to: "2026-03-10").value["items"].sole["hours"]
    end
  end

  test "a partial or malformed date is refused" do
    assert_equal "to must be a date like 2026-03-31", hours(:admin, team_id: @alpha.neat_id, to: "2026-03").error
    assert_equal "from must be a date like 2026-03-31", hours(:admin, team_id: @alpha.neat_id, from: "9" * 200).error
  end

  test "the window is 366 days at most, both ends counted" do
    assert_not hours(:admin, team_id: @alpha.neat_id, from: "2025-01-01", to: "2026-01-01").error?
  end
end
