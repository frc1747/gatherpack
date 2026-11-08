require "application_system_test_case"
require "my_gatherpack_test_helper"
require_relative "../support/signups_world"

class MyGatherpackSignupsSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper
  include SignupsWorld

  # config.hosts allows localhost in test, but not Capybara's 127.0.0.1.
  setup do
    @saved_app_host = Capybara.app_host
    @saved_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    travel_to Time.zone.parse("2026-10-20 09:00")
    turn_on_my_gatherpack
    build_signups_world
  end

  teardown do
    restore_my_gatherpack
    Capybara.app_host = @saved_app_host
    Capybara.always_include_port = @saved_include_port
  end

  test "a sign-up is listed under Coming up and opens its sheet" do
    sheet = create_world_sheet
    create_world_signup(sheet.signup_positions.create!(name: "Cashier", capacity: 2), :worker)
    sign_in person(:worker).user

    visit root_path
    within("[data-home-column=coming_up]") { click_link "Cashier" }

    assert_current_path signup_sheet_path(sheet)
  end
end
