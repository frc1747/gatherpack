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

  test "a member signs up, then cancels" do
    sign_in person(:student).user
    visit signup_sheet_path(@sheet)

    click_on "Sign up"
    fill_in "Anything the organizers should know?", with: "Running late"
    click_button "Sign up"

    assert_text "You're signed up for Cashier."
    within "#my_signups" do
      assert_text "Cashier"
    end
    assert_text "1 of 3 filled"

    accept_confirm { click_on "Cancel" }

    assert_text "Your sign-up was cancelled."
    assert_no_selector "#my_signups"
    assert Signup.find_by!(person: person(:student)).cancelled?
  end

  test "on a sheet open to anyone, a member picks who it's on behalf of by typing a name" do
    @sheet.on_behalf_of_anyone!
    sign_in person(:student).user
    visit signup_sheet_path(@sheet)

    click_on "Sign up"
    find("#on_behalf_of_picker input[role=combobox]").fill_in(with: "Two")
    find("[role=option]", text: "StudentTwo World").click
    click_on "Sign up"

    assert_text "You're signed up for Cashier."
    assert_equal person(:student2), Signup.find_by!(person: person(:student)).on_behalf_of
  end

  test "an organizer adds a date with no time yet, then sets its time" do
    restore = apply_settings(signups_organizers: "Sheet Organizer > Club")
    sign_in person(:worker).user
    @sheet.signup_sheet_organizers.create!(person: person(:worker))
    visit edit_signup_sheet_path(@sheet)

    click_on "Add dates"
    find("select[name=dates_event_type_id] option[value='#{event_types(:one).id}']").select_option
    within "#date_row_0" do
      fill_in "Date", with: Date.new(2026, 11, 7)
      fill_in "Name", with: "Picnic"
    end
    click_on "Add these dates"

    assert_text "1 date added."
    within "#dates" do
      assert_text "Sat Nov 7, 2026, time not set yet"
      within find("li", text: "Picnic") do
        click_on "Change"
      end
    end
    fill_in "Starts", with: Time.zone.parse("2026-11-07 11:00")
    fill_in "Ends", with: Time.zone.parse("2026-11-07 15:00")
    click_on "Save"

    assert_text "Picnic saved."
    within("#dates") { assert_text "Sat Nov 7, 2026 11:00 AM" }
  ensure
    restore&.call
  end
end
