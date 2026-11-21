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
    assert_select "[data-activity-meetings]", text: "Meetings: 1 of 1 · 2 h"
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

  test "the season start's description has no format instructions" do
    assert_no_match(/MM-DD/, Settings.get(:my_gatherpack_season_start).description)
  end

  test "the season start shows as a month and day and saves the same text" do
    skip "needs the settings inputs seam" unless Settings.respond_to?(:input) && Settings.input_for(:my_gatherpack_season_start)

    Settings.set(:my_gatherpack_season_start, "09-15")
    sign_in person(:admin).user

    get settings_path
    assert_response :success
    assert_select "select[name='settings[my_gatherpack_season_start][month]'] option[value='9'][selected]"
    assert_select "select[name='settings[my_gatherpack_season_start][day]'] option[value='15'][selected]"

    patch settings_path, params: { settings: { my_gatherpack_season_start: { month: "9", day: "15" } } }
    assert_equal "09-15", Settings[:my_gatherpack_season_start]
  end

  # Content

  test "the page's blocks come in order: what you've done, then requirements" do
    sign_in person(:member).user
    get activity_path

    blocks = css_select("[data-activity-block]").map { |block| block["data-activity-block"] }
    assert_equal %w[done checklists], blocks
    assert_select "[data-activity-block=checklists] .mg-heading", text: "Requirements"
    assert_select "[data-activity-block=checklists] a", text: "Fall Requirements"
    assert_select "[data-activity-block=history]", count: 0
    assert_select "[data-activity-tile]", count: 0
  end

  test "an outreach event shows under Outreach with its date, name, place and hours" do
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-kind=#{@outreach.neat_id}]" do
      assert_select "[data-activity-kind-total]", text: "Outreach: 2 events · 6 h"
      assert_select "[data-activity-line]", count: 2
      assert_select "[data-activity-line]:first-of-type .mg-row-title", text: "Library demo"
      assert_select "[data-activity-line]", text: /Food drive\s+Sat Oct 3 · Town Hall · 3 h · Checked in/
      assert_select "[data-activity-line] [data-activity-counts]", text: "Counts toward Outreach events", count: 2
    end
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-kind-total]", text: "Build: 1 event"
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-line]", text: /Build day\s+Sat Sep 12 · All day · Checked in/
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-not-required]", text: "Not required for you"
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-counts]", count: 0
  end

  test "each kind's section has an anchor, and the jump links point to them" do
    sign_in person(:member).user
    get activity_path

    [ @build, @outreach ].each do |type|
      assert_select "##{"kind-#{type.neat_id}"}[data-activity-kind=#{type.neat_id}]"
      assert_select "[data-activity-jump] a[href='#kind-#{type.neat_id}']", text: type.name
    end
  end

  test "meetings are one line, not a line per punch or meeting" do
    TimeClockPunch.create!(person: person(:member), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-13 18:00"), end_time: Time.zone.parse("2026-10-13 19:30"))
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-meetings]", count: 1
    assert_select "[data-activity-meetings]", text: "Meetings: 1 of 1 · 3.5 h"
    assert_select "[data-activity-kind=meetings]", count: 0
    assert_select "[data-activity-line]", text: /Tuesday meeting|Fall meetings/, count: 0
  end

  test "submitted forms aren't in what you've done" do
    form = Form.create!(title: "Photo release", team: @members, respond_permission: "family", read_permission: "family", status: :draft)
    response = FormResponse.create!(form: form, subject: person(:member))
    FormSubmission.create!(form_response: response, number: 1, form_version: form.content_version, status: :active, submitted_at: Time.zone.parse("2026-10-20 12:00"))
    sign_in person(:member).user
    get activity_path

    assert_response :success
    assert_select "[data-activity-block=done]", text: /Photo release/, count: 0
    assert_select "[data-activity-line]", count: 3
  end

  test "a sign-up marked done shows as signed up under its kind" do
    sheet = SignupSheet.create!(title: "Demo crew", team: @members, status: :open)
    fair = create_activity_event("Science fair", "2026-11-01 09:00", @outreach, hours: 4)
    sheet.signup_sheet_events.create!(event: fair)
    position = sheet.signup_positions.create!(name: "Booth", capacity: 5)
    Signup.create!(signup_slot: position.signup_slots.find_by!(event: fair), person: person(:member), signed_up_by: person(:member), status: :fulfilled)
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-kind=#{@outreach.neat_id}] [data-activity-kind-total]", text: "Outreach: 3 events · 10 h"
    assert_select "[data-activity-line=signed_up]", text: /Science fair\s+Sun Nov 1 · 4 h · Signed up/
  end

  test "a sign-up marked done says what it counts toward, and one nothing counts says nothing" do
    build_concessions_signups
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-line=signed_up]", text: /Stocking.*Counts toward Concessions shifts/m
    assert_select "[data-activity-line=signed_up]", text: /Shelving/ do |lines|
      assert_select lines.first, "[data-activity-counts]", count: 0
    end
  end

  test "a ward's sign-up marked done says what it counts toward on the guardian's view" do
    build_concessions_signups(:kid, read_level: "family")
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_select "[data-activity-line=signed_up]", text: /Stocking.*Counts toward Concessions shifts/m
    assert_select "[data-activity-line=signed_up] [data-activity-counts]", count: 1
  end

  test "an all-day event says All day and adds no hours, even with a punch that day" do
    whole_day = create_activity_event("Concessions day", "2026-10-24 00:00", @build, hours: 24)
    whole_day.checkins.create!(person: person(:member))
    TimeClockPunch.create!(person: person(:member), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-24 10:00"), end_time: Time.zone.parse("2026-10-24 14:00"))
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-line]", text: /Concessions day\s+Sat Oct 24 · All day · Checked in/
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-kind-total]", text: "Build: 2 events"
    assert_no_match(/24 h/, response.body)

    get root_path
    assert_select "[data-activity-uncounted=#{@build.neat_id}]", text: "Build: 2 events"
  end

  test "nothing this season says so" do
    sign_in person(:outsider).user
    get activity_path

    assert_select "[data-activity-nothing]", text: "Nothing yet this season."
    assert_select "[data-activity-kind]", count: 0
  end

  test "an earlier season shows its records and the select lists it" do
    sign_in person(:member).user
    get activity_path(season: 2025)

    assert_select "select[name=season] option", count: 2
    assert_select "select[name=season] option[selected]", text: "2025–26"
    assert_select "[data-activity-line]", count: 1
    assert_select "[data-activity-line]", text: /Spring fair/
  end

  test "the season select submits on change, with a hidden Show button for when scripts are off" do
    sign_in person(:member).user
    get activity_path

    assert_select "form.mg-activity-season select[name=season][onchange='this.form.requestSubmit()']"
    assert_select "form.mg-activity-season input[type=submit][value=Show].btn-secondary.d-none"
    assert_select "form.mg-activity-season .btn-primary", false
  end

  test "a ward's page has no punches and no meetings, and links only events the guardian can open" do
    @meeting.checkins.create!(person: person(:kid))
    @outreach1.checkins.create!(person: person(:kid))
    TimeClockPunch.create!(person: person(:kid), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-06 18:00"), end_time: Time.zone.parse("2026-10-06 20:00"))
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_select "[data-activity-block=done] .mg-heading", text: "What they've done"
    assert_select "[data-activity-meetings]", count: 0
    assert_no_match "Meetings", response.body
    assert_select "[data-activity-line]", count: 1
    assert_select "[data-activity-line]", text: /Fall meetings|Tuesday meeting/, count: 0
    assert_select "[data-activity-kind=#{@outreach.neat_id}] [data-activity-line]", text: /Food drive\s+Sat Oct 3 · Town Hall · 3 h · Checked in/
    assert_select "[data-activity-line] a[href='#{event_path(@outreach1)}']", count: 0
  end

  test "a ward's counted kind the guardian can't see the item for says nothing; an uncounted one says 'for them'" do
    @outreach1.checkins.create!(person: person(:kid))
    @build_day.checkins.create!(person: person(:kid))
    refresh(@requirements)
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_select "[data-activity-kind=#{@outreach.neat_id}] [data-activity-counts]", count: 0
    assert_select "[data-activity-kind=#{@build.neat_id}] [data-activity-not-required]", text: "Not required for them"
    assert_no_match "Outreach events", response.body
  end

  test "a ward's checklist hidden from the guardian is never named, and what it counts isn't 'not required'" do
    @requirements.update!(read_level: "self_and_leaders")
    @outreach1.checkins.create!(person: person(:kid))
    refresh(@requirements)
    sign_in person(:parent).user
    get activity_path(person: person(:kid).neat_id)

    assert_response :success
    assert_no_match "Fall Requirements", response.body
    assert_no_match "Outreach events", response.body
    assert_select "[data-activity-kind=#{@outreach.neat_id}] [data-activity-counts]", count: 0
    assert_select "[data-activity-kind=#{@outreach.neat_id}] [data-activity-not-required]", count: 0
    assert_select "[data-activity-block=checklists]", count: 0
  end

  test "the member's own events link when they can open them" do
    sign_in person(:member).user
    get activity_path

    assert_select "[data-activity-line] a[href='#{event_path(@outreach1)}']", text: "Food drive"
  end

  # Menu

  test "My activity is in the menu's top group, right after Home, while the page is on" do
    menu = MyGatherpack::Menu.new(person(:member).user)
    assert_equal [ "Home", "My activity" ], menu.top.map(&:label).first(2)

    with_settings(feature_my_gatherpack_activity: "false") do
      assert_not_includes MyGatherpack::Menu.new(person(:member).user).top.map(&:label), "My activity"
    end
  end

  # Home

  test "Home and the activity page agree on what no checklist counts" do
    sign_in person(:member).user
    get root_path
    home = css_select("[data-activity-uncounted]").map { |row| row["data-activity-uncounted"] }
    assert_select "[data-activity-uncounted=#{@build.neat_id}][href='#{activity_path(anchor: "kind-#{@build.neat_id}")}']", text: "Build: 1 event"
    assert_select "[data-activity-link]", text: "See all your activity"

    get activity_path
    page = css_select("[data-activity-not-required]").map { |row| row["data-activity-not-required"] }

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
