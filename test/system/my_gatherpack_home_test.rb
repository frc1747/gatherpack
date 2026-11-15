require "application_system_test_case"
require "my_gatherpack_test_helper"
require_relative "../support/checklists_world"

class MyGatherpackHomeSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper
  include ChecklistsWorld

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

  test "My Season opens Done with its button and shows a line's detail when tapped" do
    build_checklists_world
    Settings[:feature_checklists] = "true"
    checklist = create_world_checklist("Trip")
    add_rule(checklist, :include, :person, person_id: person(:member).id)
    add_item(checklist, :has_login, "Login")
    refresh(checklist)
    sign_in person(:member).user

    visit root_path

    within "[data-home-section=checklists-season]" do
      assert_text "You're all set for now"
      button = find("button.mg-season-done", text: "Login")
      assert_equal "false", button["aria-expanded"]
      assert_no_selector "summary", text: "Login", visible: true
      assert_operator button.evaluate_script("this.getBoundingClientRect().height"), :>=, 44

      button.click
      assert_selector "button.mg-season-done[aria-expanded=true]"
      line = find("summary", text: /Login\s+✓ Complete/)
      assert_operator line.evaluate_script("this.getBoundingClientRect().height"), :>=, 44
      assert_no_text "Has a login with an email"

      line.click
      assert_text "Has a login with an email"
      assert_link "Open the checklist", href: checklist_path(checklist)
    end
  end
end
