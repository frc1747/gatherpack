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

  test "on desktop the sidebar carries the site name, every section is open, and search stays in it on every page" do
    login = create_login("Morgan")
    sign_in login
    visit root_path

    assert_no_selector ".mg-home-tools input[type=search]"
    within ".sidebar" do
      assert_selector "input[type=search]"
    end

    visit person_path(login.person)
    within ".sidebar" do
      assert_text "Northwind Community"
      assert_selector "input[type=search]"
      assert_link "Shortcuts"
      assert_no_text "More"
    end
    assert_no_selector "header.navbar"
  end

  test "a folded Manage part stays folded after a reload" do
    manager = create_login("Riley")
    Membership.create!(person: manager.person, team: teams(:one), manager: true)
    sign_in manager
    visit root_path

    within "[data-menu-part=people]" do
      assert_link "Badges"
      click_button "People"
      assert_no_link "Badges"
    end

    visit root_path
    within "[data-menu-part=people]" do
      assert_selector "button[aria-expanded=false]", text: "People"
      assert_no_link "Badges"
    end
    within("[data-menu-part=money]") { assert_link "Ledgers" }
  end

  # Headless Chrome reports no hover, like a phone, so the pins come from Edit menu.
  test "Edit menu shows the pins, and a pin pins an item to the top or unpins it" do
    sign_in create_login("Morgan")
    visit root_path
    assert_no_selector "button[aria-label='Pin Calendar to the top']"

    click_button "Edit menu"
    find("[data-menu-group=top] button[aria-label='Pin Calendar to the top']").click
    within("[data-menu-group=pinned]") { assert_link "Calendar" }
    within("[data-menu-group=top]") { assert_link "Calendar" }

    find("[data-menu-group=pinned] button[aria-label='Unpin Calendar']").click
    assert_no_selector "[data-menu-group=pinned]"
    assert_selector "button[aria-pressed=true]", text: "Edit menu"
  end
end
