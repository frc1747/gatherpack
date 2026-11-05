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
end
