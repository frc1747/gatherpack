require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  test "destroy removes an event with check-ins and their field responses" do
    event = events(:one)
    checkin = checkins(:one)
    response = checkin_field_responses(:one)

    assert_difference -> { Event.count }, -1 do
      delete event_url(event)
    end

    assert_redirected_to calendar_index_url
    assert_not Checkin.exists?(checkin.id)
    assert_not CheckinFieldResponse.exists?(response.id)
    assert AuditLog.exists?(item_type: "Checkin", item_id: checkin.id, event: "destroy")
  end

  test "delete confirm states the number of check-ins" do
    get event_url(events(:one))

    assert_response :success
    assert_select "a[data-turbo-confirm=?]", "Delete this event and its 1 check-in?"
  end

  test "delete confirm pluralizes the number of check-ins" do
    other = Person.create!(first_name: "Pat", last_name: "Plural")
    Checkin.create!(event: events(:one), person: other, created_by: users(:one))

    get event_url(events(:one))

    assert_select "a[data-turbo-confirm=?]", "Delete this event and its 2 check-ins?"
  end

  test "delete confirm stays generic without check-ins" do
    events(:one).checkins.destroy_all

    get event_url(events(:one))

    assert_select "a[data-turbo-confirm=?]", "Are you sure?"
  end
end
