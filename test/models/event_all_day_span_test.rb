require "test_helper"

class EventAllDaySpanTest < ActiveSupport::TestCase
  setup do
    @original_zone = Time.zone
    Time.zone = "America/Chicago"
  end

  teardown { Time.zone = @original_zone }

  test "an all_day event is an all day span" do
    event = build_event(time_kind: "all_day", start_time: at("2026-11-07 09:00"))
    event.valid?

    assert_predicate event, :all_day_span?
    assert_not_predicate event, :time_tba?
  end

  test "a tba event is not an all day span" do
    event = build_event(time_kind: "tba", start_time: at("2026-11-07 09:00"))
    event.valid?

    assert_predicate event, :time_tba?
    assert_not_predicate event, :all_day_span?
  end

  test "a timed event with real times is not an all day span" do
    assert_not_predicate build_event(start_time: at("2026-11-07 18:00"), end_time: at("2026-11-07 20:00")), :all_day_span?
  end

  test "a timed event from 00:00 to 23:59 is an all day span" do
    assert_predicate build_event(start_time: at("2026-11-07 00:00"), end_time: at("2026-11-07 23:59")), :all_day_span?
  end

  test "a timed event from 00:00 to the end of a later day is an all day span" do
    assert_predicate build_event(start_time: at("2026-11-07 00:00"), end_time: at("2026-11-09 00:00").end_of_day), :all_day_span?
  end

  test "a timed event from 00:00 to the next 00:00 is an all day span" do
    assert_predicate build_event(start_time: at("2026-11-07 00:00"), end_time: at("2026-11-08 00:00")), :all_day_span?
  end

  test "a real event from 00:00 to 02:00 stays timed" do
    assert_not_predicate build_event(start_time: at("2026-11-07 00:00"), end_time: at("2026-11-07 02:00")), :all_day_span?
  end

  test "a timed event that starts after midnight is not an all day span" do
    assert_not_predicate build_event(start_time: at("2026-11-07 00:30"), end_time: at("2026-11-08 00:00")), :all_day_span?
  end

  test "a timed event without an end time is not an all day span" do
    assert_not_predicate build_event(start_time: at("2026-11-07 00:00"), end_time: nil), :all_day_span?
  end

  test "midnight to midnight holds on the day clocks spring forward" do
    assert_predicate build_event(start_time: at("2026-03-08 00:00"), end_time: at("2026-03-09 00:00")), :all_day_span?
  end

  test "midnight to midnight holds on the day clocks fall back" do
    assert_predicate build_event(start_time: at("2026-11-01 00:00"), end_time: at("2026-11-02 00:00")), :all_day_span?
    assert_predicate build_event(start_time: at("2026-11-01 00:00"), end_time: at("2026-11-01 00:00").end_of_day), :all_day_span?
  end

  test "midnight is judged in the site time zone" do
    event = build_event(start_time: Time.utc(2026, 11, 7, 6), end_time: Time.utc(2026, 11, 8, 6))

    assert_predicate event, :all_day_span?
    Time.use_zone("UTC") { assert_not_predicate event, :all_day_span? }
  end

  private

  def at(string)
    Time.zone.parse(string)
  end

  def build_event(**attributes)
    Event.new(name: "Meet", event_type: event_types(:one), team: teams(:one), **attributes)
  end
end
