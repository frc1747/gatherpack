require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemovePunchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @manager_period = TimeClockPeriod.create!(name: "Alpha Managers", team: @alpha, start_time: Time.utc(2026, 3, 1), end_time: Time.utc(2026, 3, 31), permission: :added_by_manager)
    @punch = create_world_punch(person(:ward), @manager_period, 10, 12)
    @admin_punch = create_world_punch(person(:ward), @alpha_period, 14, 16)
  end

  def remove(viewer, punch, **options)
    call_tool("remove_punch", user: user(viewer), punch_id: punch.neat_id, **options)
  end

  test "an admin removes any punch and gets it back marked removed" do
    result = nil
    assert_difference("TimeClockPunch.count", -1) { result = remove(:admin, @admin_punch) }

    assert_equal @admin_punch.neat_id, result.value["id"]
    assert_equal true, result.value["removed"]
    assert_equal person(:ward).neat_id, result.value.dig("person", "id")
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "TimeClockPunch", item_id: @admin_punch.id, event: "destroy").last.whodunnit
  end

  test "a team manager removes a manager period's punch, but not an added by admin one" do
    assert_difference("TimeClockPunch.count", -1) { assert_nil remove(:alpha_manager, @punch).error }
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { remove(:alpha_manager, @admin_punch) }
  end

  test "a plain member on another team and a guardian can't reach it" do
    assert_refused("Not found", TimeClockPunch, AuditLog) { remove(:beta_member, @punch) }
    assert_refused("Not found", TimeClockPunch, AuditLog) { remove(:guardian, @punch) }
  end

  test "a member removes their own in no period, but not their own in an added by admin period" do
    own = TimeClockPunch.create!(person: person(:beta_member), start_time: Time.utc(2026, 3, 10, 9))
    assert_nil remove(:beta_member, own).error

    in_period = create_world_punch(person(:beta_member), @beta_period, 20, 21)
    assert_refused("Not allowed", TimeClockPunch, AuditLog) { remove(:beta_member, in_period) }
  end

  test "a read token and the setting being off refuse it, and a bad ID is not found" do
    assert_refused("Not allowed", TimeClockPunch) { remove(:admin, @punch, scopes: "mcp_read") }
    assert_refused("Writes disabled", TimeClockPunch) { remove(:admin, @punch, writes_enabled: false) }
    assert_refused("Not found", TimeClockPunch) { call_tool("remove_punch", user: user(:admin), punch_id: person(:ward).neat_id) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @admin_punch ],
      [ :alpha_manager, @punch ],
      [ :alpha_manager, @admin_punch ],
      [ :beta_member, @punch ],
      [ :guardian, @punch ]
    ].each do |viewer, punch|
      page = page_changes_rows?(TimeClockPunch, as: user(viewer)) { delete time_clock_punch_path(punch) }
      tool = changes_rows?(TimeClockPunch) { remove(viewer, punch) }

      assert_equal page, tool, "#{viewer} removing #{punch.neat_id}"
    end
  end
end
