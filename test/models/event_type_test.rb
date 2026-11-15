require "test_helper"

class EventTypeTest < ActiveSupport::TestCase
  test "destroying a type removes its check-in fields" do
    event_type = EventType.create!(name: "Workshop")
    event_type.checkin_fields.create!(name: "T-shirt size")

    assert_difference "CheckinField.count", -1 do
      event_type.destroy!
    end
  end

  test "a type with no events whose check-in fields kept answers is destroyed with them" do
    event_type = event_types(:one)
    # Moving the event away (skipping callbacks) leaves its checkin's response on the old type's field.
    events(:one).update_column(:event_type_id, event_types(:two).id)
    assert event_type.events.empty?
    response = checkin_field_responses(:one)
    assert_equal checkin_fields(:one), response.checkin_field
    assert_equal 1, event_type.checkin_answer_count

    assert_difference "AuditLog.where(item_type: 'CheckinFieldResponse', event: 'destroy').count", 1 do
      event_type.destroy!
    end
    assert_not CheckinField.exists?(checkin_fields(:one).id)
    assert_not CheckinFieldResponse.exists?(response.id)
  end
end
