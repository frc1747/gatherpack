require "test_helper"

class EventTypeTest < ActiveSupport::TestCase
  test "destroying a type removes its check-in fields" do
    event_type = EventType.create!(name: "Workshop")
    event_type.checkin_fields.create!(name: "T-shirt size")

    assert_difference "CheckinField.count", -1 do
      event_type.destroy!
    end
  end

  test "a type whose check-in fields have responses is not destroyed" do
    event_type = event_types(:one)
    # Moving the event away (skipping callbacks) leaves its checkin's response on the old type's field.
    events(:one).update_column(:event_type_id, event_types(:two).id)
    assert event_type.events.empty?
    assert CheckinFieldResponse.exists?(checkin_field: checkin_fields(:one))

    assert_no_difference [ "EventType.count", "CheckinField.count", "CheckinFieldResponse.count" ] do
      assert_not event_type.destroy
    end
    assert_includes event_type.errors.full_messages, "Cannot delete an event type whose check-in fields have responses"
  end
end
