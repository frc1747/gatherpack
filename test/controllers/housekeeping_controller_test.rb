require "test_helper"
require_relative "../support/checklists_world"

class HousekeepingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    build_checklists_world
    @trip = create_world_checklist("Trip 2026", starts_on: Date.new(2025, 9, 1), ends_on: Date.new(2026, 6, 30))
    @old_event = Event.create!(name: "Kickoff 2025", event_type: event_types(:one), team: @club,
      start_time: Time.zone.local(2025, 9, 1, 18), end_time: Time.zone.local(2025, 9, 1, 20))
    @new_event = Event.create!(name: "Kickoff 2026", event_type: event_types(:one), team: @club,
      start_time: 2.days.ago, end_time: 2.days.ago + 2.hours)
    @alumni = create_world_team("Alumni", parent: @club)
  end

  def with_housekeeping(**settings, &block)
    with_settings(feature_checklists: "true", feature_housekeeping: "true", feature_events: "true", **settings, &block)
  end

  test "with the feature off its pages send people away and list pages show no bar" do
    with_settings(feature_events: "true") do
      sign_in person(:admin).user
      [ housekeeping_list_path(:events), housekeeping_purge_path(:denied_applications), team_move_people_path(@members) ].each do |path|
        get path
        assert_redirected_to root_path, path
      end
      post housekeeping_apply_path(:events), params: { act: "archive", ids: [ @old_event.id ] }
      assert_redirected_to root_path
      assert_nil @old_event.reload.archived_at

      get events_path
      assert_no_match "archive, restore or copy", response.body
    end
  end

  test "the list page bar leads to the old ones, filtered by the shared date control" do
    with_housekeeping do
      sign_in person(:club_manager).user
      get events_path
      assert_match "Old events: archive, restore or copy several at once", response.body
      assert_select "input[name='older[mode]'][value='within']"

      get housekeeping_list_path(:events, older: { mode: "date", date: "2025-12-31" })
      assert_response :success
      assert_select "input[name='ids[]'][value='#{@old_event.id}']"
      assert_select "input[name='ids[]'][value='#{@new_event.id}']", count: 0

      get housekeeping_list_path(:events, older: { mode: "within", amount: "6", unit: "months" })
      assert_select "input[name='ids[]'][value='#{@old_event.id}']"
      assert_select "input[name='ids[]'][value='#{@new_event.id}']", count: 0
    end
  end

  test "archive selected previews, then archives, and the list hides them" do
    with_housekeeping do
      sign_in person(:club_manager).user
      post housekeeping_preview_path(:events), params: { act: "archive", ids: [ @old_event.id ] }
      assert_response :success
      assert_match "1 event will be archived.", response.body
      assert_nil @old_event.reload.archived_at

      post housekeeping_apply_path(:events), params: { act: "archive", ids: [ @old_event.id ] }
      assert_redirected_to housekeeping_list_path(:events)
      assert @old_event.reload.archived_at

      get events_path
      assert_no_match "Kickoff 2025", response.body
      assert_match "Kickoff 2026", response.body
      get event_path(@old_event)
      assert_response :success

      get housekeeping_list_path(:events, archived: "1")
      assert_select "input[name='ids[]'][value='#{@old_event.id}']"
      post housekeeping_apply_path(:events), params: { act: "restore", ids: [ @old_event.id ], archived: "1" }
      assert_nil @old_event.reload.archived_at
    end
  end

  test "the preview names a checklist skipped because another requires it" do
    with_housekeeping do
      prep = create_world_checklist("Travel prep")
      add_item(prep, :checklist, "Trip done", { checklist_id: @trip.id })
      sign_in person(:club_manager).user

      post housekeeping_preview_path(:checklists), params: { act: "archive", ids: [ @trip.id ] }
      assert_match "0 checklists will be archived. 1 skipped.", response.body
      assert_match "Trip 2026: still used by Travel prep", response.body

      post housekeeping_apply_path(:checklists), params: { act: "archive", ids: [ @trip.id ] }
      assert @trip.reload.active?
    end
  end

  test "records outside the person's view aren't touched" do
    with_housekeeping do
      outside = Event.create!(name: "Elsewhere", event_type: event_types(:one), team: @other_org, start_time: 1.year.ago, end_time: 1.year.ago + 1.hour)
      sign_in person(:club_manager).user
      post housekeeping_apply_path(:events), params: { act: "archive", ids: [ outside.id ] }
      assert_nil outside.reload.archived_at
    end
  end

  test "copy selected shows the dates and the Old to New table, then makes drafts" do
    with_housekeeping do
      add_item(@trip, :badge, "Safety", { badge_ids: [ @safety.id ] })
      safety_next = create_world_badge("Safety 2027")
      sign_in person(:club_manager).user

      post housekeeping_preview_path(:checklists), params: { act: "copy", ids: [ @trip.id ], shift_months: "12" }
      assert_response :success
      assert_match "1 checklist will be copied as drafts, dates moved on 1 year.", response.body
      assert_match I18n.l(Date.new(2027, 6, 30), format: :long), response.body
      assert_select "select[name='replace[Badge:#{@safety.id}]'] option[selected][value='#{safety_next.id}']"

      post housekeeping_apply_path(:checklists), params: { act: "copy", ids: [ @trip.id ], shift_months: "12", replace: { "Badge:#{@safety.id}" => safety_next.id } }
      copy = Checklist.find_by!(title: "Trip 2027")
      assert copy.draft?
      assert_equal Date.new(2027, 6, 30), copy.ends_on
      assert_equal [ safety_next.id ], copy.checklist_items.first.config["badge_ids"]
    end
  end

  test "types without a copier offer no copy" do
    with_housekeeping do
      sign_in person(:admin).user
      get housekeeping_list_path(:events)
      assert_select "button[value='copy']", count: 0
      get housekeeping_list_path(:checklists)
      assert_select "button[value='copy']"
    end
  end

  # Purges

  test "purges are for admins only" do
    with_housekeeping do
      denied = MembershipApplication.create!(person: person(:member), team: @joiners)
      denied.update!(status: :denied, reviewed_at: 2.years.ago)
      sign_in person(:club_manager).user

      get team_membership_applications_path(@joiners)
      assert_no_match "Clear denied applications", response.body
      get housekeeping_purge_path(:denied_applications)
      assert_response :redirect
      post housekeeping_purge_path(:denied_applications), params: { confirmed: "1", count: "1" }
      assert_response :redirect
      assert MembershipApplication.exists?(denied.id)
    end
  end

  test "a purge shows what goes, needs confirming, and leaves an audit entry" do
    with_housekeeping do
      denied = MembershipApplication.create!(person: person(:member), team: @joiners)
      denied.update!(status: :denied, reviewed_at: 2.years.ago)
      sign_in person(:admin).user

      get team_membership_applications_path(@joiners)
      assert_match "Clear denied applications older than 12 months", response.body

      get housekeeping_purge_path(:denied_applications)
      assert_response :success
      assert_match "1 will be cleared", response.body
      assert_match person(:member).display_name, response.body

      post housekeeping_purge_path(:denied_applications), params: { count: "1" }
      assert_redirected_to housekeeping_purge_path(:denied_applications)
      assert MembershipApplication.exists?(denied.id)

      post housekeeping_purge_path(:denied_applications), params: { confirmed: "1", count: "2" }
      assert MembershipApplication.exists?(denied.id), "a count that changed since the preview asks again"

      post housekeeping_purge_path(:denied_applications), params: { confirmed: "1", count: "1" }
      assert_not MembershipApplication.exists?(denied.id)
      log = HousekeepingPurge.find_by!(key: "denied_applications")
      assert_equal person(:admin), log.person
      audit = AuditLog.find_by!(item_type: "HousekeepingPurge", item_id: log.id)
      assert_equal person(:admin).user.id, audit.whodunnit
    end
  end

  # Move people

  test "a manager moves selected people to another team after a preview" do
    with_housekeeping do
      Membership.create!(team: @members, person: person(:club_manager), manager: true)
      sign_in person(:club_manager).user

      get team_memberships_path(@members)
      assert_match "Move people to another team", response.body

      get team_move_people_path(@members)
      assert_response :success
      assert_select "input[name='ids[]'][value='#{person(:member).id}']"
      assert_select "input[name='ids[]'][value='#{person(:club_manager).id}']", count: 0
      assert_select "select[name='to_team_id'] option[value='#{@alumni.id}']"

      post preview_team_move_people_path(@members), params: { to_team_id: @alumni.id, ids: [ person(:member).id ] }
      assert_response :success
      assert_match "1 person will move from Members to Alumni.", response.body
      assert @members.memberships.exists?(person: person(:member))

      post team_move_people_path(@members), params: { to_team_id: @alumni.id, ids: [ person(:member).id ] }
      assert_redirected_to team_memberships_path(@members)
      assert_not @members.memberships.exists?(person: person(:member))
      assert @alumni.memberships.exists?(person: person(:member))
    end
  end

  test "the move list narrows to people with no activity since a date" do
    with_housekeeping do
      Person.where(id: @members.memberships.select(:person_id)).update_all(created_at: 3.years.ago)
      Checkin.create!(event: @new_event, person: person(:member))
      sign_in person(:admin).user

      get team_move_people_path(@members, no_activity: { mode: "within", amount: "1", unit: "months" })
      assert_select "input[name='ids[]'][value='#{person(:member2).id}']"
      assert_select "input[name='ids[]'][value='#{person(:member).id}']", count: 0
    end
  end

  test "people can only be moved to a team the mover manages" do
    with_housekeeping do
      sign_in person(:club_manager).user
      post team_move_people_path(@members), params: { to_team_id: @other_org.id, ids: [ person(:member).id ] }
      assert_redirected_to team_move_people_path(@members)
      assert @members.memberships.exists?(person: person(:member))

      sign_in person(:member).user
      post team_move_people_path(@members), params: { to_team_id: @alumni.id, ids: [ person(:member2).id ] }
      assert_response :redirect
      assert @members.memberships.exists?(person: person(:member2))
    end
  end

  test "the people list filters to no activity since a date" do
    with_housekeeping do
      Person.where(id: @members.memberships.select(:person_id)).update_all(created_at: 3.years.ago)
      Checkin.create!(event: @new_event, person: person(:member))
      sign_in person(:admin).user

      get people_path(no_activity: { mode: "within", amount: "1", unit: "months" })
      assert_match person(:member2).display_name, response.body
      assert_no_match person(:member).display_name + "<", response.body
    end
  end

  test "an archived announcement leaves the dashboard" do
    with_housekeeping do
      announcement = Announcement.create!(title: "Bring snacks", content: "Please", start_time: 1.day.ago, end_time: 1.week.from_now)
      assert_includes Announcement.visible, announcement
      Housekeeping.type(:announcements).archive!(announcement)
      assert_not_includes Announcement.visible, announcement
    end
  end
end
