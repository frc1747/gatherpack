require "application_system_test_case"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class PersonFieldsTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_person_fields_world
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "an admin sets up a field that only the right people see" do
    with_settings(feature_person_fields: "true") do
      login_as person(:admin).user
      visit new_person_field_path

      fill_in "Name", with: "Food Allergies"
      select "Short text", from: "Type"
      assert_no_field "Choices"
      select "Multiple choice", from: "Type"
      fill_in "Choices", with: "peanut\nshellfish\ngluten"
      select "This person, their guardians, and their leaders", from: "Who can see this"
      assert_text "This person, their guardians (Parent of), and the managers of their teams"
      select "This person, their guardians, and their leaders", from: "Who can edit this"
      select "Can see", from: "person_field_badge_access_#{@health_officer_badge.id}"
      click_on "Create Person field"

      assert_text "Person field was successfully created."
      field = PersonField.find_by!(key: "food_allergies")
      assert_equal({ @health_officer_badge.id => "read" }, field.badge_access)

      login_as person(:parent_a1).user
      visit edit_person_path(person(:a1))
      check "peanut"
      assert_text "A1 World can see and change this."
      click_on "Update Person"
      assert_text "Food Allergies: peanut"

      login_as person(:health_officer).user
      visit person_path(person(:a1))
      assert_text "Food Allergies: peanut"

      login_as person(:a2).user
      visit person_path(person(:a1))
      assert_text "A1 World"
      assert_no_text "Food Allergies"
      assert_no_text "peanut"
    end
  end
end
