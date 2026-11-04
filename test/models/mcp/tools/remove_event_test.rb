require "test_helper"
require_relative "../../../support/mcp_world"

class Mcp::Tools::RemoveEventTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_time_world
    @empty = create_world_event("Empty", @alpha, Time.utc(2026, 3, 20, 18))
  end

  def remove(viewer, event = @empty, **options)
    call_tool("remove_event", user: user(viewer), event_id: event.neat_id, **options)
  end

  test "an admin removes it and gets it back marked removed" do
    result = nil
    assert_difference("Event.count", -1) { result = remove(:admin) }

    assert_equal [ @empty.neat_id, "Empty", true ], result.value.values_at("id", "name", "removed")
    assert_equal user(:admin).id.to_s, AuditLog.where(item_type: "Event", item_id: @empty.id, event: "destroy").last.whodunnit
  end

  test "a team manager removes their team's" do
    assert_difference("Event.count", -1) { assert_nil remove(:alpha_manager).error }
  end

  test "check-ins refuse it, naming the count, but only to someone who may remove it" do
    assert_refused("This event has 2 check-ins, so it can't be removed", Event, AuditLog) { remove(:admin, @alpha_event) }
    create_world_checkin(person(:alpha_member), @empty)
    assert_refused("This event has 1 check-in, so it can't be removed", Event, AuditLog) { remove(:alpha_manager) }
    assert_refused("Not allowed", Event, AuditLog) { remove(:alpha_member) }
  end

  test "the page's delete fails the same way on check-ins" do
    sign_in user(:admin)
    assert_no_difference("Event.count") do
      assert_raises(ActiveRecord::InvalidForeignKey) { delete event_path(@alpha_event) }
    end
  end

  test "a foreign key failure from another table is refused without a count, leaving no audit row" do
    Hook.create!(name: "Blocks", event: "events - destroy", code: "raise ActiveRecord::InvalidForeignKey, 'other table'")

    assert_refused("Other records still refer to this event, so it can't be removed", Event, AuditLog) { remove(:admin) }
  end

  test "a plain member sees it but can't remove it" do
    assert_refused("Not allowed", Event, AuditLog) { remove(:alpha_member) }
  end

  test "a member on another team and a guardian can't reach it" do
    assert_refused("Not found", Event, AuditLog) { remove(:beta_member) }
    assert_refused("Not found", Event, AuditLog) { remove(:guardian) }
  end

  test "a read token, the setting being off and a bad ID refuse it" do
    assert_refused("Not allowed", Event) { remove(:admin, scopes: "mcp_read") }
    assert_refused("Writes disabled", Event) { remove(:admin, writes_enabled: false) }
    assert_refused("Not found", Event) { call_tool("remove_event", user: user(:admin), event_id: person(:ward).neat_id) }
  end

  test "it runs the event's hooks" do
    assert_hook_runs("events - destroy") { remove(:admin) }
  end

  test "it allows and refuses as the page does" do
    %i[admin alpha_manager alpha_member beta_member guardian].each do |viewer|
      page = page_changes_rows?(Event, as: user(viewer)) { delete event_path(@empty) }
      tool = changes_rows?(Event) { remove(viewer) }

      assert_equal page, tool, viewer.to_s
    end
  end
end
