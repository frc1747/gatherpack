require "test_helper"
require "my_gatherpack_test_helper"

class MyGatherpackHoursTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  setup do
    host! "localhost"
    @saved_zone = Settings.get(:time_zone).instance_variable_get(:@value)
    turn_on_my_gatherpack
    Settings[:time_zone] = "America/New_York"
    @member = create_login("Morgan")
    @period = TimeClockPeriod.create!(name: "November", start_time: Date.new(2026, 11, 1), end_time: Date.new(2026, 11, 30), permission: :added_by_user)
    punch = TimeClockPunch.new(person: @member.person, time_clock_period: @period, start_time: Time.utc(2026, 11, 10, 14), end_time: Time.utc(2026, 11, 10, 16))
    punch.created_by = "kiosk"
    punch.save!
    sign_in @member
  end

  teardown do
    restore_my_gatherpack
    Settings.get(:time_zone).instance_variable_set(:@value, @saved_zone)
  end

  test "the total is there all evening on the period's last day, in the site's zone" do
    travel_to Time.find_zone("America/New_York").local(2026, 11, 30, 21) do
      get time_clock_punches_path

      assert_select ".mg-hours-total-label", text: "Hours in November"
    end
  end

  test "the total isn't there the evening before the period starts" do
    travel_to Time.find_zone("America/New_York").local(2026, 10, 31, 21) do
      get time_clock_punches_path

      assert_select ".mg-hours-total", false
    end
  end

  test "the footer shows New, Search and Clear Search, with Time Clock Periods alone in More for a member" do
    get time_clock_punches_path

    assert_select ".card-footer > a.btn-success", text: "New Time Clock Punch"
    assert_select ".card-footer input[type=submit][value=Search]"
    assert_select ".card-footer a.btn-dark", text: "Clear Search"
    assert_select ".card-footer .mg-hours-more .dropdown-toggle", text: "More"
    assert_select ".mg-hours-more .dropdown-item", count: 1
    assert_select ".mg-hours-more .dropdown-item[href=?]", time_clock_periods_path, text: "Time Clock Periods"
    assert_select ".card-footer a.btn-info, .card-footer a.btn-warning", false
  end

  test "a manager's More holds Time Clock Periods, Flag Review and Time Clock Kiosk" do
    team = Team.create!(name: "Den A", team_type: team_types(:one))
    Membership.create!(person: @member.person, team: team, manager: true)

    get time_clock_punches_path

    assert_select ".mg-hours-more .dropdown-item", count: 3
    assert_select ".mg-hours-more .dropdown-item[href=?]", time_clock_periods_path, text: "Time Clock Periods"
    assert_select ".mg-hours-more .dropdown-item[href=?]", flagged_time_clock_punches_path, text: "Flag Review"
    assert_select ".mg-hours-more a.dropdown-item[data-turbo=false][href=?]", time_kiosk_path, text: "Time Clock Kiosk"
  end

  test "an admin gets all three in More without managing a team" do
    sign_in create_login("Avery", admin: true)

    get time_clock_punches_path

    assert_select ".mg-hours-more .dropdown-item", count: 3
    assert_select ".mg-hours-more .dropdown-item[href=?]", flagged_time_clock_punches_path, text: "Flag Review"
    assert_select ".mg-hours-more .dropdown-item[href=?]", time_kiosk_path, text: "Time Clock Kiosk"
  end
end
