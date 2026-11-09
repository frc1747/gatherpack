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
end
