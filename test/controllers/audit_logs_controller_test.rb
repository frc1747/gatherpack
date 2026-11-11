require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = people(:one).user
    @admin.update!(admin: true)
    sign_in @admin
    @event = Event.create!(name: "Deleted event", start_time: 1.day.ago, event_type: event_types(:one))
  end

  test "a deleted record's audit log names who deleted it and shows its last state" do
    assert_difference -> { AuditLog.where(item_id: @event.id, event: "destroy").count }, 1 do
      delete event_url(@event)
    end
    log = AuditLog.where(item_id: @event.id, event: "destroy").last
    assert_equal @admin.id, log.whodunnit

    get audit_log_url(log)

    assert_response :success
    assert_select "li", text: /destroy/
    assert_select "a", text: "Revert"
  end

  test "reverting a deleted record's audit log restores the record" do
    delete event_url(@event)
    log = AuditLog.where(item_id: @event.id, event: "destroy").last

    post revert_audit_log_url(log)

    assert_equal "Deleted event", Event.find(@event.id).name
  end
end
