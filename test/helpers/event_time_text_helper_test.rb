require "test_helper"

class EventsHelperTest < ActionView::TestCase
  include ApplicationHelper
  include FontAwesomeHelper

  setup do
    @original_zone = Time.zone
    Time.zone = "America/Chicago"
  end

  teardown { Time.zone = @original_zone }

  test "event_time_text gives a range for a timed event" do
    event = timed("2026-11-07 18:00", "2026-11-07 20:00")

    assert_equal "6:00 PM – 8:00 PM", event_time_text(event)
    assert_equal "November 7, 2026, 6:00 PM – 8:00 PM", event_time_text(event, date: true)
  end

  test "event_time_text gives the start alone without an end" do
    assert_equal "6:00 PM", event_time_text(timed("2026-11-07 18:00", nil))
  end

  test "event_time_text gives both dates for a multi-day timed event" do
    event = timed("2026-11-07 18:00", "2026-11-08 09:00")

    assert_equal "November 7, 2026, 6:00 PM – November 8, 2026, 9:00 AM", event_time_text(event, date: true)
  end

  test "event_time_text reads an all_day event as all day" do
    event = Event.new(time_kind: "all_day", start_time: at("2026-11-07 00:00"), end_time: at("2026-11-07 00:00").end_of_day)

    assert_equal "All day", event_time_text(event)
    assert_equal "November 7, 2026, All day", event_time_text(event, date: true)
  end

  test "event_time_text reads a tba event as time TBA" do
    event = Event.new(time_kind: "tba", start_time: at("2026-11-07 00:00"), end_time: at("2026-11-07 00:00").end_of_day)

    assert_equal "Time TBA", event_time_text(event)
    assert_equal "November 7, 2026, Time TBA", event_time_text(event, date: true)
  end

  test "event_time_text reads timed midnight spans as all day" do
    [ [ "2026-11-07 00:00", "2026-11-07 23:59" ], [ "2026-03-08 00:00", "2026-03-09 00:00" ] ].each do |from, to|
      assert_equal "All day", event_time_text(timed(from, to)), "#{from} to #{to}"
    end
  end

  test "event_time_text names the last day of a multi-day all day span" do
    event = timed("2026-11-07 00:00", "2026-11-10 00:00")

    assert_equal "November 7, 2026 – November 9, 2026, All day", event_time_text(event, date: true)
  end

  test "event_time_text keeps a real event from 00:00 to 02:00 timed" do
    assert_equal "12:00 AM – 2:00 AM", event_time_text(timed("2026-11-07 00:00", "2026-11-07 02:00"))
  end

  test "the other helpers read a timed midnight-to-midnight event as all day" do
    event = timed("2026-11-07 00:00", "2026-11-07 23:59")

    assert_equal "November 7, 2026", event_time_summary(event)
    assert_not format_event_time_date(event, :short, false).include?("23:59")
    assert_equal true, event_calendar_times(event)[:allDay]
    assert_includes event_as_badge(event), "(2026-11-07)"
  end

  test "the other helpers keep a real event timed" do
    event = timed("2026-11-07 00:00", "2026-11-07 02:00")

    assert_equal "12:00 AM November 7, 2026", event_time_summary(event)
    assert_equal false, event_calendar_times(event)[:allDay]
  end

  private

  def at(string)
    Time.zone.parse(string)
  end

  def timed(from, to)
    Event.new(name: "Meet", time_kind: "timed", start_time: at(from), end_time: to && at(to))
  end
end
