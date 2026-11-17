require "test_helper"

# A sign-up row's time: an all-day or TBA event says so, and only a sign-up
# date with no time yet says "Time not set yet".
class MyGatherpackSignupTimeTest < ActionView::TestCase
  include MyGatherpackSignupsHelper

  def event(start_time, end_time, time_kind: nil)
    Event.new(name: "Concessions", start_time: start_time, end_time: end_time).tap do |e|
      e.time_kind = time_kind if time_kind
    end
  end

  test "all-day and TBA events read as such; a date with no time yet is not set" do
    day = Time.zone.local(2026, 11, 21)
    assert_equal "Time not set yet", my_gatherpack_signup_time(event(day, day.change(hour: 23, min: 59)))
    assert_equal "6:00 PM", my_gatherpack_signup_time(event(day.change(hour: 18), day.change(hour: 20)))
    skip "needs feature/event-time-display" unless Event.column_names.include?("time_kind")

    assert_equal "All day", my_gatherpack_signup_time(event(day, day.end_of_day, time_kind: "all_day"))
    assert_equal "Time TBA", my_gatherpack_signup_time(event(day, day.end_of_day, time_kind: "tba"))
  end
end
