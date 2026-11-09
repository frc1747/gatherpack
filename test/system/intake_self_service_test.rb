require "application_system_test_case"
require_relative "../support/intake_world"

class IntakeSelfServiceTest < ApplicationSystemTestCase
  include IntakeWorld

  setup do
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_intake_world
    Intake.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    @restore_settings = SettingsTestHelper.apply(feature_intake: "true")
  end

  teardown do
    @restore_settings&.call
    Intake.rate_limit_store = nil
    Capybara.app_host = nil
  end

  test "a parent signs up, confirms their email, and adds a child" do
    visit intake_join_path(@registration.slug)
    check "Mentors"
    fill_in "First name", with: "Morgan"
    fill_in "Last name", with: "Lee"
    fill_in "Email", with: "morgan.lee@gmial.com"
    find_field("First name").click
    assert_text "Did you mean morgan.lee@gmail.com?"
    fill_in "Email", with: "morgan.lee@example.com"
    find_field("First name").click
    assert_no_text "Did you mean"
    sleep Intake::FormGuard::MINIMUM_SECONDS # people take longer than this to fill the form in
    click_on "Continue"

    assert_text "Thanks, Morgan. Check your email to finish."
    assert_nil User.find_by(email: "morgan.lee@example.com")

    token = Intake::Entry.sole.issue_token!
    visit intake_verification_path(token: token)
    fill_in "Password", with: "Password1!"
    fill_in "Password again", with: "Password1!"
    click_on "Finish"

    assert_text "You're signed in."
    assert_text "Mentors: Waiting for a guardian" # no birthday on file yet
    fill_in "Your birthday", with: "1985-05-06"
    click_on "Save"
    assert_text "Mentors: Waiting for review"

    within(".card", text: "Anyone else joining with you?") do
      check "Juniors"
      fill_in "First name", with: "Sam"
      fill_in "Last name", with: "Lee"
      fill_in "Birthday", with: "2014-02-03"
      click_on "Add"
    end

    assert_text "Added Sam."
    assert_text "Sam Lee"
    assert_text "Juniors: Waiting for review"
    morgan = User.find_by!(email: "morgan.lee@example.com").person
    assert_equal [ "Sam" ], morgan.wards.pluck(:first_name)
  end
end
