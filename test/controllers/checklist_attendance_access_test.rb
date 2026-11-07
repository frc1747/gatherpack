require "test_helper"
require_relative "../support/checklists_world"

# An attendance result carries hours: in full to those who could see the
# person's punches in the app and to holders of a full grant on the
# checklist, status only to anyone else the checklist lets see it. Only
# admins and managers of the checklist's team set one up.
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

  test "people who could see the punches see everything; a guardian sees only the status" do
    full = seen_by(person(:kid))
    assert full.full?
    assert_equal "25% of 2 h", full.summary
    assert_equal 0.5, full.measures["credited"]
    assert seen_by(person(:admin)).full?
    assert seen_by(person(:club_manager)).full?, "manages Club, so the teams below it"

    guardian = seen_by(person(:parent))
    assert_equal "not_met", guardian.status, "the guardian still sees whether it's done"
    assert_not guardian.full?
    assert_nil guardian.summary
    assert_nil guardian.detail
    assert_nil guardian.measures
    assert Checklists.status_for(@checklist, [ person(:kid) ], viewer: person(:parent))[person(:kid).id].item(@login.id).full?,
      "other items are untouched"

    assert_nil seen_by(person(:crew_manager)), "the checklist doesn't show the kid to another team's manager at all"
  end

  test "a full grant on the checklist sees everything for the item; a status grant sees the status" do
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @item.id ], access: :full)
    give_badge(:outsider, @viewer_badge)
    @checklist.checklist_grants.create!(team: @crew, item_ids: [ @item.id ], access: :status)

    granted = seen_by(person(:outsider))
    assert granted.full?, "as the report Page shows its viewers today"
    assert_equal "25% of 2 h", granted.summary

    status_grant = seen_by(person(:organizer))
    assert_equal "not_met", status_grant.status
    assert_nil status_grant.summary

    other = add_item(@checklist, :attendance, "Spring", { rules: [ { name: "Spring", share: "10" } ] })
    @checklist.checklist_grants.create!(badge: @viewer_badge, item_ids: [ @login.id, other.id ], access: :status)
    assert_equal :status, Checklists::Kinds::Attendance.cap_levels(other, person(:outsider), [ person(:kid).id ])[person(:kid).id],
      "a full grant on one item doesn't open another"
  end

  test "the report shows a guardian the status without the hours" do
    with_feature do
      sign_in person(:parent).user
      get person_checklists_path(person(:kid))
      assert_response :success
      assert_match "Attendance", response.body
      assert_no_match "25% of 2 h", response.body
      assert_no_match "Fall:", response.body

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

  private

  def seen_by(viewer)
    Checklists.status_for(@checklist, [ person(:kid) ], viewer: viewer)[person(:kid).id]&.item(@item.id)
  end
end
