require "test_helper"
require_relative "../support/checklists_world"

# The housekeeping screens follow the screen standard: a breadcrumb back to
# the list instead of a Back link, a secondary Cancel before the action, and
# tables that scroll on phones.
class HousekeepingScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @trip = create_world_checklist("Trip 2026", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
    @old_event = Event.create!(name: "Kickoff 2025", event_type: event_types(:one), team: @club,
      start_time: Time.zone.local(2025, 9, 1, 18), end_time: Time.zone.local(2025, 9, 1, 20))
  end

  test "the list has a breadcrumb back to its list page and no Back link" do
    with_housekeeping do
      sign_in person(:club_manager).user
      get housekeeping_list_path(:events, older: { mode: "" })

      assert_response :success
      assert_select ".breadcrumb a[href=?]", events_path, text: "Events"
      assert_select ".table-responsive[data-controller~=column-chooser][data-column-chooser-key-value=housekeeping-events]"
      assert_select "a", text: /Back to/, count: 0
      assert_select ".btn-link", text: /Back/, count: 0
      assert_select ".table-responsive table"
      assert_select "input.btn-secondary[value=Find]"
    end
  end

  test "the preview cancels with a secondary button and archives" do
    with_housekeeping do
      sign_in person(:club_manager).user
      post housekeeping_preview_path(:events), params: { act: "archive", ids: [ @old_event.id ] }

      assert_select ".breadcrumb", text: /Old events/
      assert_select "a.btn-secondary[href^=?]", housekeeping_list_path(:events), text: "Cancel"
      assert_select "a.btn-link", count: 0
      assert_select "a.btn-secondary + input.btn-primary[value=?]", "Archive 1"

      get housekeeping_list_path(:events, older: { mode: "" })
      assert_response :success

      post housekeeping_apply_path(:events), params: { act: "archive", ids: [ @old_event.id ] }
      assert @old_event.reload.archived_at
    end
  end

  test "the copy preview's tables scroll on phones" do
    with_housekeeping do
      sign_in person(:club_manager).user
      post housekeeping_preview_path(:checklists), params: { act: "copy", ids: [ @trip.id ], shift_months: "12" }

      assert_response :success
      assert_select ".table-responsive table"
    end
  end

  test "a purge has a table that scrolls, Cancel and the Clear button" do
    with_housekeeping do
      denied = MembershipApplication.create!(person: person(:member), team: @joiners)
      denied.update!(status: :denied, reviewed_at: 2.years.ago)
      sign_in person(:admin).user

      get housekeeping_purge_path(:denied_applications)
      assert_response :success
      assert_select ".table-responsive table"
      assert_select "a.btn-secondary", text: "Cancel"
      assert_select "input.btn-danger[value=?]", "Clear 1"
    end
  end

  test "moving people: a table that scrolls, then Cancel before the action on both steps" do
    alumni = create_world_team("Alumni", parent: @club)
    with_housekeeping do
      sign_in person(:club_manager).user

      get team_move_people_path(@members)
      assert_response :success
      assert_select ".table-responsive table input[name='ids[]'][value=?]", person(:member).id
      assert_select "input.btn-secondary[value=Find]"
      assert_select "a.btn-secondary[href=?] + input.btn-primary[value=?]", team_memberships_path(@members), "Check the move"
      assert_select ".btn-link", count: 0

      post preview_team_move_people_path(@members), params: { to_team_id: alumni.id, ids: [ person(:member).id ] }
      assert_response :success
      assert_select "a.btn-secondary[href=?] + input.btn-primary[value=?]", team_move_people_path(@members), "Move 1"
      assert_select ".btn-link", count: 0
    end
  end

  private

  def with_housekeeping(**settings, &block)
    with_settings(feature_checklists: "true", feature_housekeeping: "true", feature_events: "true", **settings, &block)
  end
end
