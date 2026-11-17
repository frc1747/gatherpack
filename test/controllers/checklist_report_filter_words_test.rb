require "test_helper"
require_relative "../support/checklists_world"

# A column's filter lists the words its badges show, so a result that says
# "Below minimum" is filtered under "Below minimum", not a generic status word.
class ChecklistReportFilterWordsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @checklist = create_world_checklist("Trip", starts_on: Date.new(2026, 9, 1))
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @period = TimeClockPeriod.create!(name: "Season", start_time: Date.new(2026, 9, 1), end_time: Date.new(2027, 6, 30), permission: :added_by_admin)
    meeting = Event.create!(name: "Kickoff", event_type: event_types(:one), team: @club, time_clock_period: @period,
      start_time: Time.zone.parse("2026-10-05 18:00"), end_time: Time.zone.parse("2026-10-05 20:00"))
    TimeClockPunch.create!(person: person(:kid), time_clock_period: @period, created_by: person(:admin),
      start_time: meeting.start_time, end_time: meeting.start_time + 30.minutes)
    @item = add_item(@checklist, :attendance, "Attendance", { rules: [ { name: "Fall", share: "60" } ] })
    travel_to(Time.zone.parse("2026-10-10 12:00")) { refresh(@checklist) }
  end

  test "the filter option for a below-minimum result reads like its badge" do
    with_feature do
      sign_in person(:admin).user
      get checklist_path(@checklist)

      column = css_select("thead th").index { |heading| heading.text.include?("Attendance") }
      cell = css_select("tbody tr").filter_map { |row| row.css("td")[column] }.find { |td| td["data-status"] == "not_met" }
      assert_equal "Below minimum", cell.at_css(".badge").text.strip

      option = css_select("input[data-checklist-report-target=tick][data-column='#{column}'][value=not_met]").map { |box| box.parent.text.squish }
      assert_equal [ "Below minimum (4)" ], option
    end
  end
end
