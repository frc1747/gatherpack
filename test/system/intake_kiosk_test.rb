require "application_system_test_case"
require_relative "../support/intake_world"

class IntakeKioskTest < ApplicationSystemTestCase
  include IntakeWorld
  include Warden::Test::Helpers

  setup do
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_intake_world
    @registration.update!(kiosk: true)
    Intake.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @restore_settings = SettingsTestHelper.apply(feature_intake: "true", intake_idle_seconds: "3")
    login_as @leader.user
  end

  teardown do
    @restore_settings&.call
    Intake.rate_limit_store = nil
    Capybara.app_host = nil
    Warden.test_reset!
  end

  def fill_in_person(first_name:, email:, birth_year:)
    check "Juniors"
    fill_in "First name", with: first_name
    fill_in "Last name", with: "Fox"
    fill_in "Year you were born", with: birth_year
    fill_in "Your email", with: email
    fill_in "Your email again", with: email
  end

  test "people sign up in the room, one after another, and managers see them waiting" do
    visit intake_kiosk_path(@registration.slug)
    assert_no_text @leader.display_name

    fill_in_person(first_name: "Jamie", email: "jamie@example.com", birth_year: Date.current.year - 13)
    click_on "Done"
    assert_text "Enter a guardian's name and email."
    fill_in "Guardian's first name", with: "Robin"
    fill_in "Guardian's last name", with: "Fox"
    fill_in "Guardian's email", with: "robin.fox@example.com"
    click_on "Done"
    assert_text "Thanks, Jamie. Check your email to finish."

    click_on "Next person"
    fill_in_person(first_name: "Casey", email: "casey@example.com", birth_year: 1988)
    fill_in "Your email again", with: "casey@exampel.com"
    click_on "Done"
    assert_text "The two emails don't match."
    fill_in "Your email again", with: "casey@example.com"
    click_on "Done"
    assert_text "Thanks, Casey. Check your email to finish."

    # Left alone, the screen clears itself for the next person.
    visit intake_kiosk_path(@registration.slug)
    fill_in "First name", with: "Half typed"
    assert_field "First name", with: "", wait: 6

    visit waiting_intake_registration_path(@registration)
    assert_text "Jamie Fox"
    assert_text "Casey Fox"
    assert_text "Waiting for a guardian (Robin)"
  end
end
