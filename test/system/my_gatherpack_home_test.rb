require "application_system_test_case"
require "my_gatherpack_test_helper"

class MyGatherpackHomeSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    turn_on_my_gatherpack
  end

  teardown do
    restore_my_gatherpack
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "home greets the member, with its own styles loaded" do
    login = create_login("Morgan")
    Membership.create!(person: login.person, team: teams(:one))
    Event.create!(name: "Team Meeting", start_time: 1.day.from_now, event_type: event_types(:one), team: teams(:one))
    sign_in login

    visit root_path

    assert_selector "h1", text: "Hi Morgan. You're all caught up."
    assert_selector ".mg-heading", text: "COMING UP"
    assert_link "Team Meeting"
    assert_equal "uppercase", evaluate_script("getComputedStyle(document.querySelector('.mg-heading')).textTransform")
  end
end
