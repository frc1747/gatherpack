require "test_helper"

class EventTypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  test "admin deletes an event type with check-in fields and no events" do
    event_type = EventType.create!(name: "Workshop")
    event_type.checkin_fields.create!(name: "T-shirt size")

    assert_difference [ "EventType.count", "CheckinField.count" ], -1 do
      delete event_type_url(event_type)
    end

    assert_redirected_to event_types_url
  end

  test "an event type whose check-in fields have responses is refused with a message" do
    event_type = event_types(:one)
    events(:one).update_column(:event_type_id, event_types(:two).id)

    assert_no_difference [ "EventType.count", "CheckinField.count", "CheckinFieldResponse.count" ] do
      delete event_type_url(event_type)
    end

    assert_redirected_to event_type_url(event_type)
    assert_equal "Cannot delete an event type whose check-in fields have responses", flash[:alert]
  end

  test "an event type with events is not deleted" do
    event_type = EventType.create!(name: "Workshop")
    Event.create!(name: "Build day", start_time: 1.day.from_now, event_type: event_type)

    assert_no_difference "EventType.count" do
      delete event_type_url(event_type)
    end

    assert_redirected_to root_url
    assert_equal "You are not allowed to do that", flash[:notice]
  end
end
