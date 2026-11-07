require "test_helper"
require_relative "../support/checklists_world"

# An attendance result carries hours, so it shows only to those who could
# see the person's punches in the app; only admins and managers of the
# checklist's team set one up.
class ChecklistAttendanceAccessTest < ActionDispatch::IntegrationTest
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
    @login = add_item(@checklist, :has_login, "Login")
    travel_to(Time.zone.parse("2026-10-10 12:00")) { refresh(@checklist) }
  end

  test "the person, admins and their team's managers see the result; guardians and grant holders don't" do
    seen_by = ->(viewer) { Checklists.status_for(@checklist, [ person(:kid) ], viewer: viewer)[person(:kid).id]&.item(@item.id) }

    assert_equal "25% of 2 h", seen_by.call(person(:kid)).summary
    assert seen_by.call(person(:admin))
    assert seen_by.call(person(:club_manager)), "manages Club, so the teams below it"

    assert_nil seen_by.call(person(:crew_manager)), "manages another team"
    assert_nil seen_by.call(person(:parent)), "the app doesn't show a guardian their ward's punches"
    assert Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:parent))[person(:kid).id].item(@login.id),
      "the guardian still sees the other items"

    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @item.id ], access: :full)
    give_badge(:outsider, @viewer_badge)
    assert_nil seen_by.call(person(:outsider)), "a grant doesn't get past the cap"
  end

  test "the report leaves the hours out for a viewer who can't see them" do
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @item.id, @login.id ], access: :full)
    give_badge(:outsider, @viewer_badge)

    with_feature do
      sign_in person(:outsider).user
      get checklist_path(@checklist)
      assert_response :success
      assert_no_match "25% of 2 h", response.body
      assert_no_match "Below minimum", response.body

      sign_in person(:club_manager).user
      get checklist_path(@checklist)
      assert_match "25% of 2 h", response.body
    end
  end

  test "only admins and managers of the checklist's team set up an attendance item" do
    with_settings(feature_checklists: "true", checklists_organizers: "Checklist Organizer > Club") do
      @checklist.checklist_organizers.create!(person: person(:organizer))
      params = { confirmed: "1", checklist_item: { kind: "attendance", label: "Meetings", config: { rules: { "0" => { name: "Fall", share: "50" } } } } }

      sign_in person(:organizer).user
      post checklist_checklist_items_path(@checklist), params: params
      assert_response :unprocessable_entity
      assert_match "set up this item this way", response.body
      assert_not ChecklistItem.exists?(label: "Meetings")

      sign_in person(:crew_manager).user
      post checklist_checklist_items_path(@checklist), params: params
      assert_not ChecklistItem.exists?(label: "Meetings"), "managing another team isn't enough"

      sign_in person(:club_manager).user
      post checklist_checklist_items_path(@checklist), params: params
      assert ChecklistItem.exists?(label: "Meetings")
    end
  end
end
