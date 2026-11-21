require "test_helper"

class PeopleHelperTest < ActionView::TestCase
  include FontAwesomeHelper

  NAME = "<img src=x onerror=alert(1)>"

  test "person_time_clock_as_badge escapes the period name" do
    period = TimeClockPeriod.create!(name: NAME, team: teams(:one), start_time: 1.day.ago, end_time: 1.day.from_now)

    html = person_time_clock_as_badge(people(:one), 3, period)

    assert_not html.include?(NAME), "person_time_clock_as_badge emits the period name unescaped: #{html}"
    assert_includes html, "&lt;img src=x onerror=alert(1)&gt;"
    assert_includes html, %(<i class="fa-fw fa-solid fa-hourglass-half"></i>)
  end

  test "person_time_clock_as_badge counts unallocated hours without a period" do
    assert_includes person_time_clock_as_badge(people(:one), 2), "2 unallocated hours"
  end
end
