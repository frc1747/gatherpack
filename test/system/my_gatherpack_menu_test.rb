require "application_system_test_case"
require "my_gatherpack_test_helper"

class MyGatherpackMenuSystemTest < ApplicationSystemTestCase
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

  test "on desktop the sidebar carries the site name and search, and More opens" do
    sign_in create_login("Morgan")
    visit root_path

    within ".sidebar" do
      assert_text "Northwind Community"
      assert_selector "input[type=search]"
      assert_no_link "Shortcuts"
      find("summary", text: "MORE").click
      assert_link "Shortcuts"
    end
    assert_no_selector "header.navbar"
  end
end
