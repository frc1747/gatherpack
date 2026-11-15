require "test_helper"
require_relative "../support/my_gatherpack_activity_world"

# GET /activity and Home's "Also this season" (spec §7a). World:
# MyGatherpackActivityWorld; parent is the kid's guardian.
class MyGatherpackActivityPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackActivityWorld

  setup do
    host! "localhost"
    travel_to NOW
    @restore_settings = SettingsTestHelper.apply(activity_flags)
    build_activity_world
  end

  teardown do
    @restore_settings&.call
    travel_back
  end

  # Access

  test "a member gets their own page" do
    sign_in person(:member).user
    get activity_path

    assert_response :success
    assert_select "h1", text: "Your activity"
    assert_select "[data-activity-tile=meetings]", text: /2 h/
  end

  test "signing in is required" do
    get activity_path

    assert_redirected_to new_user_session_path
  end

  test "a guardian gets a current ward's page" do
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_response :success
    assert_select "h1", text: "Kid's activity"
  end

  test "anyone else asking for someone's page gets their own" do
    { member2: :member, admin: :member, club_manager: :member, member: :kid }.each do |viewer, subject|
      sign_in person(viewer).user
      get activity_path(person: person(subject).neat_id)

      assert_redirected_to activity_path, "#{viewer} asking for #{subject}"
    end
  end

  test "a former guardian gets their own page" do
    Relationship.where(parent: person(:parent), child: person(:kid)).destroy_all
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_redirected_to activity_path
  end

  test "an unknown person id gets the viewer's own page" do
    sign_in person(:member).user
    get activity_path(person: "per_nonsense")

    assert_response :success
    assert_select "h1", text: "Your activity"
  end

  test "with the flag off the page redirects home and Home has no link or Also this season" do
    sign_in person(:member).user
    with_settings(feature_my_gatherpack_activity: "false") do
      get activity_path
      assert_redirected_to root_path

      get root_path
      assert_response :success
      assert_select "[data-home-section=activity]", count: 0
      assert_select "a[href='#{activity_path}']", count: 0
      assert_no_match "Also this season", response.body
    end
  end

  test "the flag is registered off by default" do
    feature = GatherPack::Features.all.find { |entry| entry.key == :my_gatherpack_activity }

    assert_not feature.default_enabled
    assert_equal "05-01", Settings.get(:my_gatherpack_season_start).default_value
  end

  # Content

  test "the page's blocks come in order" do
    sign_in person(:member).user
    get activity_path

    blocks = css_select("[data-activity-block]").map { |block| block["data-activity-block"] }
    assert_equal %w[totals kinds history checklists], blocks
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-counts]", text: "Not required for you"
    assert_select "[data-activity-kind=#{@outreach.neat_id}] [data-activity-counts]", text: "Counts toward Outreach events"
    assert_select "[data-activity-kind=#{@build.neat_id}]", text: /1 event · —/
    assert_select "[data-activity-block=checklists] a", text: "Fall Requirements"
  end

  test "a kind of event filters History" do
    sign_in person(:member).user
    get activity_path(kind: @build.neat_id)

    assert_select "[data-activity-entry]", count: 1
    assert_select "[data-activity-entry]", text: /Build day/
    assert_select "[data-activity-kind=#{@build.neat_id}][aria-current=true]"
  end

  test "an earlier season shows its records and the select lists it" do
    sign_in person(:member).user
    get activity_path(season: 2025)

    assert_select "select[name=season] option", count: 2
    assert_select "select[name=season] option[selected]", text: "2025–26"
    assert_select "[data-activity-entry]", count: 1
    assert_select "[data-activity-entry]", text: /Spring fair/
  end

  test "a ward's page has no punches and no meeting hours, and links only events the guardian can open" do
    @meeting.checkins.create!(person: person(:kid))
    @outreach1.checkins.create!(person: person(:kid))
    TimeClockPunch.create!(person: person(:kid), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-06 18:00"), end_time: Time.zone.parse("2026-10-06 20:00"))
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_select "[data-activity-tile=meetings]", count: 0
    assert_select "[data-activity-kind=meetings]", count: 0
    assert_select "[data-activity-entry]", count: 2
    assert_select "[data-activity-entry]", text: /Fall meetings/, count: 0
    assert_select "[data-activity-entry]", text: /Food drive\s+Outreach · Town Hall/
    assert_select "[data-activity-entry] a[href='#{event_path(@outreach1)}']", count: 0
  end

  test "the member's own events link when they can open them" do
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-entry] a[href='#{event_path(@outreach1)}']", text: "Food drive"
  end

  # Home

  test "Home and the activity page agree on what no checklist counts" do
    sign_in person(:member).user
    get root_path
    home = css_select("[data-activity-uncounted]").map { |row| row["data-activity-uncounted"] }
    assert_select "[data-activity-uncounted=#{@build.neat_id}]", text: "Build: 1 event"
    assert_select "[data-activity-link]", text: "See all your activity →"

    get activity_path
    page = css_select("[data-activity-kind]").select { |row| row.at_css("[data-activity-counts]")&.text == "Not required for you" }
      .map { |row| row["data-activity-kind"] }

    assert_equal [ @build.neat_id ], home
    assert_equal home, page
  end

  test "a checklist that doesn't cover the person is never named on Home or the page" do
    sign_in person(:member).user
    get root_path
    assert_response :success
    assert_no_match "Crew Trip", response.body
    assert_no_match "Build shifts", response.body

    get activity_path
    assert_no_match "Crew Trip", response.body
    assert_no_match "Build shifts", response.body
    assert_select "a[href='#{checklist_path(@crew_trip)}']", count: 0
  end

  test "the family page links each ward's activity" do
    sign_in person(:parent).user
    get family_path

    assert_select "[data-family-activity][href='#{activity_path(person: person(:kid).neat_id)}']", text: "Activity"
    with_settings(feature_my_gatherpack_activity: "false") { get family_path }
    assert_select "[data-family-activity]", count: 0
  end
end
