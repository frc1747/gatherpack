require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemoveCheckinTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @checkin = Checkin.find_by!(person: person(:ward), event: @alpha_event)
  end

  def remove(viewer, checkin = @checkin, **options)
    call_tool("remove_checkin", user: user(viewer), checkin_id: checkin.neat_id, **options)
  end

  test "an admin removes it and gets it back marked removed" do
    result = nil
    assert_difference("Checkin.count", -1) { result = remove(:admin) }

    assert_equal [ @checkin.neat_id, person(:ward).neat_id, @alpha_event.neat_id, true ],
      [ result.value["id"], result.value.dig("person", "id"), result.value.dig("event", "id"), result.value["removed"] ]
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Checkin", item_id: @checkin.id, event: "destroy").last.whodunnit
  end

  test "the team's manager removes it, and the person checked in can, even on a locked event" do
    assert_difference("Checkin.count", -1) { assert_nil remove(:alpha_manager).error }

    own = Checkin.find_by!(person: person(:alpha_member), event: @alpha_event)
    @alpha_event.update!(locked: true)
    assert_difference("Checkin.count", -1) { assert_nil remove(:alpha_member, own).error }
  end

  test "a teammate sees it but can't remove it" do
    assert_refused("Not allowed", Checkin, AuditLog) { remove(:alpha_member) }
  end

  test "a member on another team and a guardian can't reach it" do
    assert_refused("Not found", Checkin, AuditLog) { remove(:beta_member) }
    assert_refused("Not found", Checkin, AuditLog) { remove(:guardian) }
  end

  test "a person's own check-in at a team-less event can't be reached, as on the page" do
    own = Checkin.find_by!(person: person(:alpha_member), event: @open_event)
    assert_refused("Not found", Checkin, AuditLog) { remove(:alpha_member, own) }
  end

  test "a read token, the setting being off and a bad ID refuse it" do
    assert_refused("Not allowed", Checkin) { remove(:admin, scopes: "mcp_read") }
    assert_refused("Writes disabled", Checkin) { remove(:admin, writes_enabled: false) }
    assert_refused("Not found", Checkin) { call_tool("remove_checkin", user: user(:admin), checkin_id: @alpha_event.neat_id) }
  end

  test "it runs the check-in's hooks" do
    assert_hook_runs("checkins - destroy") { remove(:admin) }
  end

  test "it allows and refuses as the page does" do
    [
      [ :admin, @checkin ],
      [ :alpha_manager, @checkin ],
      [ :ward, @checkin ],
      [ :alpha_member, @checkin ],
      [ :beta_member, @checkin ],
      [ :guardian, @checkin ],
      [ :alpha_member, Checkin.find_by!(person: person(:alpha_member), event: @open_event) ]
    ].each do |viewer, checkin|
      page = page_changes_rows?(Checkin, as: user(viewer)) { delete event_checkin_path(checkin.event, checkin) }
      tool = changes_rows?(Checkin) { remove(viewer, checkin) }

      assert_equal page, tool, "#{viewer} removing #{checkin.neat_id}"
    end
  end
end
