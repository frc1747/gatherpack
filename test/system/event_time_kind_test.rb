require "application_system_test_case"

class EventTimeKindSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    @capybara_host = [ Capybara.app_host, Capybara.always_include_port ]
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: user, first_name: "Ada", last_name: "Admin")
    sign_in user
  end

  teardown { Capybara.app_host, Capybara.always_include_port = @capybara_host }

  test "choosing all day or TBA swaps the time fields for a date" do
    visit new_event_path

    assert_field "event_start_time"
    assert_field "event_end_time"
    assert_no_field "event_event_date"

    fill_in "event_start_time", with: Time.zone.local(2026, 11, 7, 14, 0)
    choose "Time to be announced"

    assert_no_field "event_start_time"
    assert_no_field "event_end_time"
    assert_field "event_event_date", with: "2026-11-07"

    choose "All day"
    assert_no_field "event_start_time"

    fill_in "event_event_date", with: Date.new(2026, 11, 21)
    choose "At a set time"

    assert_field "event_start_time", with: "2026-11-21T14:00"
    assert_no_field "event_event_date"
  end

  test "the date follows the start date when it is edited" do
    visit new_event_path

    fill_in "event_start_time", with: Time.zone.local(2026, 11, 7, 14, 0)
    choose "Time to be announced"
    assert_field "event_event_date", with: "2026-11-07"

    choose "At a set time"
    fill_in "event_start_time", with: Time.zone.local(2026, 11, 8, 14, 0)
    choose "All day"

    assert_field "event_event_date", with: "2026-11-08"
  end

  test "returning an all-day event to a set time leaves the end empty" do
    event = Event.create!(name: "Fair", event_type: event_types(:one), team: teams(:one), time_kind: "all_day", start_time: Time.zone.local(2026, 11, 7))

    visit edit_event_path(event)
    assert_no_field "event_end_time"

    choose "At a set time"
    assert_field "event_end_time", with: ""
    fill_in "event_start_time", with: Time.zone.local(2026, 11, 9, 14, 0)
    click_on "Update Event"

    assert_text "Event was successfully updated."
    event.reload
    assert_predicate event, :timed?
    assert_nil event.end_time
    assert_equal 14, event.start_time.hour
  end
end
