require "test_helper"
require_relative "../support/my_gatherpack_activity_world"

class MyGatherpackActivityTest < ActiveSupport::TestCase
  include MyGatherpackActivityWorld

  setup do
    travel_to NOW
    @restore_settings = SettingsTestHelper.apply(activity_flags)
    build_activity_world
    @season = MyGatherpack::Season.current
  end

  teardown do
    @restore_settings&.call
    travel_back
  end

  def activity_for(name, viewer: name)
    MyGatherpack::Activity.new(person(name), season: @season, viewer: person(viewer))
  end

  # Season

  test "the season starts on May 1 by default and a record on that day belongs to the new season" do
    assert_equal Date.new(2026, 5, 1), @season.starts_on
    assert_equal Date.new(2027, 4, 30), @season.ends_on
    assert_equal "2026–27", @season.label
    assert @season.cover?(Time.zone.parse("2026-05-01 00:00"))
    assert_not @season.cover?(Time.zone.parse("2026-04-30 23:59"))
    assert_equal Date.new(2025, 5, 1), MyGatherpack::Season.containing(Date.new(2026, 4, 30)).starts_on
  end

  test "the season follows the setting" do
    with_settings(my_gatherpack_season_start: "08-15") do
      assert_equal Date.new(2026, 8, 15), MyGatherpack::Season.current.starts_on
      assert_equal Date.new(2026, 8, 15), MyGatherpack::Season.containing(Date.new(2026, 8, 15)).starts_on
      assert_equal Date.new(2025, 8, 15), MyGatherpack::Season.containing(Date.new(2026, 8, 14)).starts_on
    end
  end

  test "an unreadable setting falls back to May 1" do
    with_settings(my_gatherpack_season_start: "someday") do
      assert_equal Date.new(2026, 5, 1), MyGatherpack::Season.current.starts_on
    end
  end

  test "the seasons are this one and earlier ones holding records" do
    seasons = activity_for(:member).seasons

    assert_equal [ Date.new(2026, 5, 1), Date.new(2025, 5, 1) ], seasons.map(&:starts_on)
    assert_equal [ Date.new(2026, 5, 1) ], activity_for(:member2).seasons.map(&:starts_on)
  end

  # By kind of event

  test "meetings come first, then event types, with events, hours and what counts them" do
    rows = activity_for(:member).kind_rows

    assert_equal [ "Meetings", "Build", "Outreach" ], rows.map(&:name)
    meetings, build, outreach = rows
    activity = activity_for(:member)
    assert_equal [ 1, 2.0 ], [ meetings.events, meetings.hours ]
    assert_equal [ 1, nil, [] ], [ build.events, build.hours, activity.counts_toward(build) ]
    assert_equal [ 2, 6.0, [ "Outreach events" ] ], [ outreach.events, outreach.hours, activity.counts_toward(outreach) ]
    assert_nil outreach.uncounted
  end

  test "an event's hours are its length only when it's timed" do
    assert_equal 3.0, MyGatherpack::Activity.event_hours(@outreach1)
    assert_nil MyGatherpack::Activity.event_hours(@build_day)
  end

  test "totals count the season's records only" do
    activity = activity_for(:member)

    assert_equal 3, activity.event_count
    assert_equal 6.0, activity.event_hours
    assert_equal 2.0, activity.meeting_hours
    assert_equal [ 1, 1 ], [ activity.meetings_attended, activity.meetings_held.size ]
  end

  # Uncounted

  test "uncounted is the event types no covering count item counts, never meetings" do
    rows = MyGatherpack::Activity.uncounted(person(:member), @season)

    assert_equal [ "Build" ], rows.map(&:name)
    assert_equal [ @build.neat_id ], rows.map(&:key)
  end

  test "uncounted reads the person's stored results, not each checklist's status" do
    calls = 0
    original = Checklists.method(:checklist_for)
    Checklists.singleton_class.define_method(:checklist_for) do |*args, **options|
      calls += 1
      original.call(*args, **options)
    end

    assert_equal [ "Build" ], MyGatherpack::Activity.uncounted(person(:member), @season).map(&:name)
    assert_equal 0, calls, "Home's My Season already reads checklist_for; Also this season doesn't again"
  ensure
    Checklists.singleton_class.define_method(:checklist_for, original)
  end

  test "uncounted reads no punches, meetings or teams" do
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] }
    MyGatherpack::Activity.uncounted(person(:member), @season)
    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_empty queries.grep(/time_clock_punches|time_clock_period_id" IS NOT NULL|FROM "teams"|FROM "memberships"/)
  end

  test "a count item on a checklist that doesn't cover the person counts nothing for them" do
    rows = MyGatherpack::Activity.uncounted(person(:member), @season)

    assert_includes rows.map(&:name), "Build"
    activity = activity_for(:member)
    assert_not_includes activity.kind_rows.flat_map { |row| activity.counts_toward(row) }, "Build shifts"
  end

  test "a count item the person is exempt from counts nothing for them" do
    add_rule(@requirements, :exclude, :person, item: @outreach_item, person_id: person(:member).id)
    refresh(@requirements)

    assert_equal [ "Build", "Outreach" ], MyGatherpack::Activity.uncounted(person(:member), @season).map(&:name)
  end

  test "a sign-up source counts only check-ins where the person has a sign-up on its sheet" do
    second = Event.create!(name: "Second build day", time_kind: "all_day", event_date: Date.new(2026, 9, 19), event_type: @build, team: @members)
    Checkin.create!(person: person(:member), event: second)
    sheet = SignupSheet.create!(title: "Build crew", team: @members, status: :open, created_by: person(:admin))
    sheet.events << @build_day
    sheet.events << second
    position = SignupPosition.create!(signup_sheet: sheet, name: "Builder", kind: :people, position: 0)
    sheet.sync_slots!
    item = @requirements.checklist_items.new(kind: "count", label: "Build crew shifts")
    item.config_params = { base_amount: 1, unit: "shifts" }
    item.save!
    item.commitment.commitment_sources.create!(kind: "signups", subject: sheet)
    refresh(@requirements)

    rows = MyGatherpack::Activity.uncounted(person(:member), @season)
    assert_equal [ [ "Build", 2 ] ], rows.map { |row| [ row.name, row.events ] }, "a check-in with no sign-up there isn't counted"

    Signup.create!(signup_slot: position.signup_slots.find_by!(event: @build_day), person: person(:member), signed_up_by: person(:member), status: :fulfilled)
    activity = activity_for(:member)
    build = activity.kind_row(@build.neat_id)

    assert_equal [ "Build crew shifts" ], activity.counts_toward(build)
    assert_equal [ [ "Build", 1 ] ], activity.uncounted.map { |row| [ row.name, row.events ] }, "the event with no sign-up stays uncounted"
    assert_equal [ [ "Build", 1 ] ], MyGatherpack::Activity.uncounted(person(:member), @season).map { |row| [ row.name, row.events ] }
  end

  test "whether a type counts is the person's own answer, whoever looks" do
    @outreach1.checkins.create!(person: person(:kid))
    @build_day.checkins.create!(person: person(:kid))
    refresh(@requirements)
    guardian = activity_for(:kid, viewer: :parent)
    outreach = guardian.kind_row(@outreach.neat_id)

    assert_equal "self_and_leaders", @outreach_item.effective_read_level, "a count item is at leaders level by default"
    assert outreach.counted?
    assert_empty guardian.counts_toward(outreach), "the guardian can't see the item, so it isn't named"
    assert_equal [ "Build" ], guardian.uncounted.map(&:name)
    assert_equal MyGatherpack::Activity.uncounted(person(:kid), @season).map(&:key), guardian.uncounted.map(&:key)
  end

  test "a checklist hidden from the guardian still counts for the ward, unnamed" do
    @requirements.update!(read_level: "self_and_leaders")
    @outreach1.checkins.create!(person: person(:kid))
    refresh(@requirements)
    guardian = activity_for(:kid, viewer: :parent)

    assert_empty guardian.checklists
    assert guardian.kind_row(@outreach.neat_id).counted?
    assert_empty guardian.uncounted
  end

  test "last season's records stay in last season" do
    last = MyGatherpack::Activity.new(person(:member), season: MyGatherpack::Season.starting_in(2025))

    assert_equal [ "Outreach" ], last.kind_rows.map(&:name)
    assert_equal [ "Spring fair" ], last.history.map(&:title)
  end

  # History

  test "history is newest first and filters by kind" do
    activity = activity_for(:member)

    assert_equal [ "Library demo", "Fall meetings", "Tuesday meeting", "Food drive", "Build day" ], activity.history.map(&:title)
    assert_equal [ "Fall meetings", "Tuesday meeting" ], activity.history(MyGatherpack::Activity::MEETINGS).map(&:title)
    assert_equal [ "Build day" ], activity.history(@build.neat_id).map(&:title)
  end

  # A ward

  test "a guardian sees no punches and no meetings row on a ward's page" do
    @meeting.checkins.create!(person: person(:kid))
    TimeClockPunch.create!(person: person(:kid), time_clock_period: @period, created_by: person(:admin),
      start_time: Time.zone.parse("2026-10-06 18:00"), end_time: Time.zone.parse("2026-10-06 20:00"))
    activity = activity_for(:kid, viewer: :parent)

    assert_not activity.meetings?
    assert_not activity.own?
    assert_empty activity.kind_rows
    assert_empty activity.history, "no punches and no meeting check-ins"
    assert_equal 0, activity.meeting_hours
  end
end
