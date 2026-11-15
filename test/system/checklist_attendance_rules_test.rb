require "application_system_test_case"
require_relative "../support/checklists_world"

class ChecklistAttendanceRulesTest < ApplicationSystemTestCase
  include ChecklistsWorld
  include Warden::Test::Helpers

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_checklists_world
    @checklist = create_world_checklist("Trip", starts_on: Date.new(2026, 9, 1), status: :draft)
    TimeClockPeriod.create!(name: "Season", start_time: Date.new(2026, 9, 1), end_time: Date.new(2027, 6, 30), permission: :added_by_admin)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "rules are rows: add one, fill in its months and remove another" do
    with_feature do
      login_as(person(:admin).user, scope: :user)
      visit new_checklist_checklist_item_path(@checklist, kind: "attendance")

      rows = -> { all("#attendance-rules tbody tr") }
      assert_equal 1, rows.call.size
      within(rows.call.first) do
        find("input[aria-label='Rule name']").fill_in(with: "Summer")
        find("input[aria-label='Share of meeting hours']").fill_in(with: "10")
        find("input[aria-label='Counted together with']").fill_in(with: "Fall")
        click_on "Fill in"
      end

      click_on "Add a rule"
      click_on "Add a rule"
      assert_equal 3, rows.call.size
      within(rows.call[1]) do
        find("input[aria-label='Rule name']").fill_in(with: "Fall")
        find("input[aria-label='Share of meeting hours']").fill_in(with: "20")
        find("select[aria-label='First month']").select("Sep")
        find("select[aria-label='Last month']").select("Dec")
        click_on "Fill in"
      end
      within(rows.call[2]) { click_on "Remove" }
      assert_equal 2, rows.call.size

      click_on "Save"
      assert_text "Attendance added."
    end

    rules = @checklist.checklist_items.find_by!(kind: "attendance").config["rules"]
    assert_equal [ "Summer", "Fall" ], rules.map { |rule| rule["name"] }
    assert_equal({ "mode" => "date", "date" => "2027-05-01" }, rules[0]["starts"], "the next May after the checklist starts")
    assert_equal "2027-08-31", rules[0]["ends_on"]
    assert_equal({ "mode" => "date", "date" => "2026-09-01" }, rules[1]["starts"])
    assert_equal "2026-12-31", rules[1]["ends_on"]
  end
end
