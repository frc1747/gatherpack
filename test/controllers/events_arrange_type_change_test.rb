require "test_helper"

class EventsArrangeTypeChangeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
    @event = events(:one)
    @event.update_columns(event_type_id: event_types(:two).id)
  end

  test "arrange and print keep responses for the previous type's fields" do
    assert_no_difference -> { CheckinFieldResponse.where(checkin_field: checkin_fields(:one)).count } do
      get arrange_event_path(@event, field_id: checkin_fields(:two).id)
      get print_event_path(@event, field_id: checkin_fields(:two).id)
    end
  end

  test "arrange adds the new type's responses" do
    get arrange_event_path(@event, field_id: checkin_fields(:two).id)
    assert_response :success
    assert checkins(:one).checkin_field_responses.exists?(checkin_field: checkin_fields(:two))
  end
end
