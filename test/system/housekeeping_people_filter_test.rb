require "application_system_test_case"
require_relative "../support/checklists_world"

# The "no activity" filter and the name search on the people list are one
# form, so either can be used first and the other keeps it.
class HousekeepingPeopleFilterTest < ApplicationSystemTestCase
  include Warden::Test::Helpers
  include ChecklistsWorld

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_checklists_world
    @idle_match = create_world_person("Idlesmith", @members)
    @busy_match = create_world_person("Busysmith", @members)
    @idle_other = create_world_person("Idlejones", @members)
    Person.where(id: [ @idle_match, @busy_match, @idle_other ].map(&:id)).update_all(created_at: 3.years.ago)
    event = Event.create!(name: "Meeting", event_type: event_types(:one), team: @club, start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
    Checkin.create!(event: event, person: @busy_match)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "search a name, then filter by no activity" do
    with_people_list do
      search_name "smith"
      within("turbo-frame#results") { assert_text "Busysmith World" }

      filter_no_activity_for_a_month
      within("turbo-frame#results") do
        assert_text "Idlesmith World"
        assert_no_text "Busysmith World"
        assert_no_text "Idlejones World"
      end
    end
  end

  test "filter by no activity, then search a name" do
    with_people_list do
      filter_no_activity_for_a_month
      within("turbo-frame#results") do
        assert_text "Idlejones World"
        assert_no_text "Busysmith World"
      end
      assert_current_path(/no_activity(%5B|\[)amount(%5D|\])=1/, url: true)

      visit current_url
      within("turbo-frame#results") do
        assert_text "Idlejones World"
        assert_no_text "Busysmith World"
      end

      search_name "smith"
      within("turbo-frame#results") do
        assert_text "Idlesmith World"
        assert_no_text "Idlejones World"
        assert_no_text "Busysmith World"
      end
    end
  end

  private

  def with_people_list
    with_settings(feature_checklists: "true", feature_housekeeping: "true") do
      login_as person(:admin).user
      visit people_path
      yield
    end
  end

  def search_name(text)
    within("form#person_search") do
      fill_in "Name", with: text
      click_on "Search"
    end
  end

  def filter_no_activity_for_a_month
    find("summary", text: "People with no activity").click
    choose "housekeeping_no_activity_within"
    fill_in "housekeeping_no_activity_amount", with: "1"
    select "months", from: "housekeeping_no_activity_unit"
    click_on "Find"
  end
end
