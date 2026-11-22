require "test_helper"
require_relative "../support/settings_test_helper"

class EventDuplicateTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SettingsTestHelper

  setup do
    host! "localhost"
    @team = Team.create!(name: "Team A", team_type: team_types(:one))
    @other = Team.create!(name: "Team B", team_type: team_types(:one))
    @admin = create_user("admin", admin: true)
    @lead = create_user("lead", team: @team, manager: true)
    @member = create_user("member", team: @team)
    @event = Event.create!(name: "Practice", location: "Shop", description: "Bring tools", checkin_limit: 5,
      locked: true, start_time: 1.day.from_now, end_time: 1.day.from_now + 2.hours,
      event_type: event_types(:one), team: @team)
  end

  test "a manager gets New Event prefilled with a copy, and nothing is saved" do
    with_settings(feature_event_duplicate: "true") do
      sign_in @lead
      assert_no_difference "Event.count" do
        get duplicate_event_path(@event)
      end
      assert_response :success
      assert_select "h1", text: "New event"
      assert_select "input[value='Practice (copy)']"
      assert_select "input[value='Shop']"
      assert_select "textarea", text: /Bring tools/
    end
  end

  test "saving the prefilled form creates the copy" do
    with_settings(feature_event_duplicate: "true") do
      sign_in @lead
      attrs = @event.duplicate_attributes.merge(start_time: 3.days.from_now, end_time: 3.days.from_now + 2.hours)
      assert_difference "Event.count", 1 do
        post events_path, params: { event: attrs }
      end
      assert_equal "Practice (copy)", Event.order(:created_at).last.name
    end
  end

  test "a member who can't create events is refused" do
    with_settings(feature_event_duplicate: "true") do
      sign_in @member
      get duplicate_event_path(@event)
      assert_redirected_to root_path
    end
  end

  test "an event outside the member's teams isn't found" do
    with_settings(feature_event_duplicate: "true") do
      other = Event.create!(name: "Other", start_time: 1.day.from_now, event_type: event_types(:one), team: @other)
      sign_in @lead
      get duplicate_event_path(other)
      assert_response :not_found
    end
  end

  test "with the feature off the action redirects" do
    sign_in @admin
    get duplicate_event_path(@event)
    assert_redirected_to root_path
  end

  test "the More menu offers Duplicate when the feature and screen standard are on" do
    with_settings(feature_event_duplicate: "true", feature_screen_standard: "true") do
      sign_in @lead
      get event_path(@event)
      assert_select ".screen-action-row .dropdown-menu a[href='#{duplicate_event_path(@event)}']", text: "Duplicate"
      assert_select ".screen-action-row > a", text: "Duplicate", count: 0
      items = css_select(".screen-action-row .dropdown-menu li").map { |li| li.text.squish }
      assert_operator items.index("Duplicate"), :<, items.index("Delete"), "Duplicate should come before Delete"
      assert_equal "Delete", items.last
    end
    with_settings(feature_screen_standard: "true") do
      get event_path(@event)
      assert_select "a[href='#{duplicate_event_path(@event)}']", count: 0
    end
  end

  test "duplicate_attributes carries an all-day event's details and leaves its check-ins behind" do
    period = TimeClockPeriod.create!(name: "Season", team: @team, start_time: 1.month.ago, end_time: 1.month.from_now)
    day = 2.days.from_now.beginning_of_day
    event = Event.create!(name: "Open house", time_kind: "all_day", start_time: day, end_time: day.end_of_day,
      location: "Hall", description: "All welcome", checkin_limit: 12, locked: true,
      event_type: event_types(:one), team: @team, time_clock_period: period)
    Checkin.create!(event: event, person: @member.person)

    copy = Event.new(event.duplicate_attributes)

    assert copy.new_record?
    assert_equal "Open house (copy)", copy.name
    assert_equal event.event_type_id, copy.event_type_id
    assert_equal @team.id, copy.team_id
    assert_equal period.id, copy.time_clock_period_id
    assert copy.all_day?
    assert_equal event.start_time, copy.start_time
    assert_equal event.end_time, copy.end_time
    assert_equal "Hall", copy.location
    assert_equal "All welcome", copy.description
    assert_equal 12, copy.checkin_limit
    assert copy.locked
    assert_empty copy.checkins
  end

  test "duplicating an all-day event keeps All day selected" do
    day = 2.days.from_now.beginning_of_day
    event = Event.create!(name: "Open house", time_kind: "all_day", start_time: day, end_time: day.end_of_day,
      event_type: event_types(:one), team: @team)
    with_settings(feature_event_duplicate: "true") do
      sign_in @lead
      get duplicate_event_path(event)
      assert_select "input[type=radio][name='event[time_kind]'][value=all_day][checked]"
    end
  end

  private
    def create_user(name, team: nil, manager: false, admin: false)
      user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
      person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
      Membership.create!(person: person, team: team, manager: manager) if team
      user
    end
end
