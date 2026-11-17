require "test_helper"

class TimeClockPeriodTest < ActiveSupport::TestCase
  setup do
    @period = TimeClockPeriod.create!(name: "Fall", start_time: Date.new(2026, 7, 1), end_time: Date.new(2026, 12, 31), team: teams(:one))
  end

  def create_event(start_time, end_time)
    Event.create!(name: "Meeting", team: teams(:one), event_type: event_types(:one), time_clock_period: @period,
                  start_time: start_time, end_time: end_time)
  end

  test "total_hours counts an evening event on the period's last day" do
    Time.use_zone("America/New_York") do
      create_event(Time.zone.local(2026, 12, 31, 18), Time.zone.local(2026, 12, 31, 21))
      assert_equal 3.0, @period.total_hours
    end
  end

  test "total_hours counts an evening event on the second-to-last day" do
    Time.use_zone("America/New_York") do
      create_event(Time.zone.local(2026, 12, 30, 18), Time.zone.local(2026, 12, 30, 21))
      assert_equal 3.0, @period.total_hours
    end
  end

  test "total_hours ignores an evening event the day before the period starts" do
    Time.use_zone("America/New_York") do
      create_event(Time.zone.local(2026, 6, 30, 20, 30), Time.zone.local(2026, 6, 30, 21, 30))
      assert_equal 0.0, @period.total_hours
    end
  end

  test "available_hours excludes events that have not ended" do
    Time.use_zone("America/New_York") do
      create_event(Time.zone.local(2026, 12, 30, 18), Time.zone.local(2026, 12, 30, 21))
      create_event(Time.zone.local(2026, 12, 31, 18), Time.zone.local(2026, 12, 31, 21))

      travel_to Time.zone.local(2026, 12, 30, 22) do
        assert_equal 3.0, @period.available_hours
        assert_equal 6.0, @period.total_hours
      end

      travel_to Time.zone.local(2026, 12, 31, 22) do
        assert_equal 6.0, @period.available_hours
      end
    end
  end
end
