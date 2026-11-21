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

  test "with the feature off the action redirects and the footer has no Duplicate" do
    sign_in @admin
    get duplicate_event_path(@event)
    assert_redirected_to root_path
  end

  test "the More menu offers Duplicate when the feature and screen standard are on" do
    with_settings(feature_event_duplicate: "true", feature_screen_standard: "true") do
      sign_in @lead
      get event_path(@event)
      assert_select "a[href='#{duplicate_event_path(@event)}']", text: "Duplicate"
    end
    with_settings(feature_screen_standard: "true") do
      get event_path(@event)
      assert_select "a[href='#{duplicate_event_path(@event)}']", count: 0
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
