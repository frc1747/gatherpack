require "application_system_test_case"
require_relative "../support/signups_world"

class SignupsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    travel_to Time.zone.parse("2026-10-01 12:00")
    build_signups_world
    @sheet = create_world_sheet(description: "Help run the stand.")
    @sheet.signup_positions.create!(name: "Cashier", capacity: 3)
  end

  test "a member signs up with an extra person, then cancels" do
    sign_in person(:student).user
    visit signup_sheet_path(@sheet)

    click_on "Sign up"
    fill_in "Anyone coming with you?", with: 1
    fill_in "Their names", with: "Sam"
    click_on "Sign up"

    assert_text "You're signed up for Cashier."
    within "#my_signups" do
      assert_text "Cashier"
      assert_text "(+1)"
    end
    assert_text "2 of 3 filled"

    accept_confirm { click_on "Cancel" }

    assert_text "Your sign-up was cancelled."
    assert_no_selector "#my_signups"
    assert Signup.last.cancelled?
  end
end
