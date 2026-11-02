require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::ClockedInNowTest < ActiveSupport::TestCase
  include McpWorld

  setup do
    build_mcp_world
    build_mcp_time_world
  end

  setup { travel_to MCP_TIME_NOW }
  teardown { travel_back }

  test "an admin sees everyone clocked in, longest first, with the period" do
    items = call_tool("clocked_in_now", user: user(:admin)).value["items"]

    assert_equal [ "AlphaManager World", "BetaMember World" ], items.map { |item| item["person"]["name"] }
    assert_equal [ 28.0, 27.0 ], items.map { |item| item["hours_so_far"] }
    assert_equal "2026-03-11T08:00:00Z", items.first["since"]
    assert_equal({ "id" => @alpha_period.neat_id, "name" => "Alpha March" }, items.first["period"])
  end

  test "a punch with no period has a null period" do
    @open_punch.update_columns(time_clock_period_id: nil)

    assert_nil call_tool("clocked_in_now", user: user(:admin)).value["items"].first["period"]
  end

  test "a team manager sees their own team's people" do
    items = call_tool("clocked_in_now", user: user(:alpha_manager)).value["items"]

    assert_equal [ "AlphaManager World" ], items.map { |item| item["person"]["name"] }
  end

  test "team filter" do
    items = call_tool("clocked_in_now", user: user(:admin), team_id: @beta.neat_id).value["items"]

    assert_equal [ "BetaMember World" ], items.map { |item| item["person"]["name"] }
  end

  test "a team outside the viewer's scope is not found" do
    @beta.update!(join_permission: :added_by_admin)

    assert_equal "Not found", call_tool("clocked_in_now", user: user(:alpha_manager), team_id: @beta.neat_id).error
  end

  test "a visible team doesn't reveal people outside the manager's reach" do
    @beta.update!(join_permission: :has_account)

    assert_empty call_tool("clocked_in_now", user: user(:alpha_manager), team_id: @beta.neat_id).value["items"]
  end

  test "the team filter doesn't list the roster of a team whose page shows no members" do
    child = create_world_team("Alpha Juniors", parent: @alpha)
    @alpha.update!(join_permission: :has_account)
    Membership.find_by!(person: person(:beta_member), team: @beta).update!(manager: true)
    Membership.create!(person: person(:alpha_manager), team: @beta)
    Membership.create!(person: person(:beta_member), team: child)

    names = ->(viewer) { call_tool("clocked_in_now", user: user(viewer), team_id: @alpha.neat_id).value["items"].map { |item| item["person"]["name"] } }

    assert_equal [ "AlphaManager World", "BetaMember World" ], names.call(:admin)
    assert_equal [ "AlphaManager World", "BetaMember World" ], names.call(:alpha_manager)
    assert_equal [ "BetaMember World" ], names.call(:beta_member), "a manager who isn't on Alpha's full page"
  end

  test "a manager of sub-teams filtering on the parent gets the members of the sub-teams they can list" do
    root = create_world_team("Root")
    root.update!(join_permission: :has_account)
    cone = create_world_team("Cone", parent: root)
    ctwo = create_world_team("Ctwo", parent: root)
    sub_mgr = create_world_person("SubMgr", cone, manager: true)
    Membership.create!(person: sub_mgr, team: ctwo, manager: true)
    sub_plain = create_world_person("SubPlain", cone)
    worker_one = create_world_person("WorkerOne", cone)
    worker_two = create_world_person("WorkerTwo", ctwo)
    root_period = create_world_period("Root March", root)
    root_manager = create_world_person("RootManager", root, manager: true)
    [ sub_mgr, sub_plain, worker_one, worker_two ].each { |person| create_world_punch(person, root_period, 9, nil) }
    names = ->(viewer) { call_tool("clocked_in_now", user: viewer.user, team_id: root.neat_id).value["items"].map { |item| item["person"]["name"].split.first }.sort }

    assert_equal %w[SubMgr SubPlain WorkerOne WorkerTwo], names.call(sub_mgr)
    assert_equal %w[SubMgr SubPlain WorkerOne WorkerTwo], names.call(root_manager), "manager of the parent team"
    assert_equal %w[SubMgr SubPlain WorkerOne WorkerTwo], names.call(person(:admin))

    Membership.create!(person: person(:badge_holder), team: cone)
    create_world_punch(person(:badge_holder), @beta_period, 9, nil)
    Membership.find_by!(person: person(:beta_member), team: @beta).update!(manager: true)
    assert_empty names.call(person(:beta_member)), "an outside manager gets nothing for someone they manage who joins the team"
  end

  test "a plain member who manages someone elsewhere keeps the filter on their own team" do
    Membership.create!(person: person(:beta_member), team: @alpha)
    Membership.find_by!(person: person(:beta_member), team: @beta).update!(manager: true)
    Membership.create!(person: person(:alpha_member), team: @beta)
    create_world_punch(person(:alpha_member), @alpha_period, 32, nil)

    items = call_tool("clocked_in_now", user: user(:beta_member), team_id: @alpha.neat_id).value["items"]

    assert_equal %w[AlphaMember BetaMember], items.map { |item| item["person"]["name"].split.first }.sort
  end

  test "a plain member is not allowed" do
    assert_equal "Not allowed", call_tool("clocked_in_now", user: user(:beta_member)).error
  end

  test "a guardian in no team is not allowed" do
    assert_equal "Not allowed", call_tool("clocked_in_now", user: user(:guardian)).error
  end

  test "closed punches are not listed" do
    TimeClockPunch.where(end_time: nil).update_all(end_time: Time.utc(2026, 3, 11, 20))

    assert_empty call_tool("clocked_in_now", user: user(:admin)).value["items"]
  end

  test "it is off with time tracking" do
    with_feature(:time_tracking, false) { assert_equal "Feature off", call_tool("clocked_in_now", user: user(:admin)).error }
  end

  test "a punch that hasn't started is not listed" do
    create_world_punch(person(:alpha_member), @alpha_period, 24 * 20, nil)

    assert_equal [ "AlphaManager World", "BetaMember World" ], call_tool("clocked_in_now", user: user(:admin)).value["items"].map { |item| item["person"]["name"] }
  end

  test "a period the viewer can't see is not named" do
    Membership.create!(person: person(:alpha_member), team: @beta)
    create_world_punch(person(:alpha_member), @beta_period, 34, nil)
    items = call_tool("clocked_in_now", user: user(:alpha_manager)).value["items"]
    item = items.find { |i| i["person"]["name"] == "AlphaMember World" }

    assert_nil item["period"]
    assert_equal "Beta March", call_tool("clocked_in_now", user: user(:admin)).value["items"].find { |i| i["person"]["name"] == "AlphaMember World" }["period"]["name"]
  end

  test "a team filter includes members of its sub-teams" do
    child = Team.create!(name: "Alpha Juniors", team_type: team_types(:one), parent: @alpha)
    junior = create_world_person("Junior", child)
    create_world_punch(junior, @everyone_period, 34, nil)
    items = call_tool("clocked_in_now", user: user(:admin), team_id: @alpha.neat_id).value["items"]

    assert_includes items.map { |item| item["person"]["name"] }, "Junior World"
  end
end
