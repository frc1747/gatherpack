require "test_helper"

class EventTimeKindTest < ActiveSupport::TestCase
  setup do
    @original_zone = Time.zone
    Time.zone = "America/Chicago"
  end

  teardown { Time.zone = @original_zone }

  test "events are timed by default and keep their times" do
    event = create_event(start_time: at("2026-11-07 14:00"), end_time: at("2026-11-07 16:30"))

    assert_predicate event, :timed?
    assert_equal at("2026-11-07 14:00"), event.start_time
    assert_equal at("2026-11-07 16:30"), event.end_time
    assert_equal 2.5, event.hours
  end

  %w[all_day tba].each do |kind|
    test "#{kind} stores the whole of the chosen day in the current zone" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"), end_time: at("2026-11-09 16:30"))

      assert_equal at("2026-11-07 00:00"), event.reload.start_time
      assert_equal at("2026-11-07 00:00").end_of_day.to_i, event.end_time.to_i
      assert_equal "2026-11-07T06:00:00Z", event.start_time.utc.iso8601
    end

    test "#{kind} takes its day from the date field over the time fields" do
      event = create_event(time_kind: kind, event_date: "2026-11-21", start_time: at("2026-11-07 14:00"))

      assert_equal at("2026-11-21 00:00"), event.start_time
    end

    test "#{kind} needs a day" do
      event = build_event(time_kind: kind, start_time: nil)

      assert_not event.valid?
      assert_predicate event.errors[:event_date], :present?
    end

    test "#{kind} has no hours" do
      assert_equal 0, create_event(time_kind: kind, start_time: at("2026-11-07 14:00")).hours
    end

    test "#{kind} is stable across saves" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))
      event = Event.find(event.id)
      event.description = "Changed"
      event.valid?

      assert_equal [ "description" ], event.changed
    end

    test "saving a real time on a #{kind} event makes it timed" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(start_time: at("2026-11-07 18:00"), end_time: at("2026-11-07 20:00"))

      event.reload
      assert_predicate event, :timed?
      assert_equal at("2026-11-07 18:00"), event.start_time
      assert_equal at("2026-11-07 20:00"), event.end_time
    end

    test "resubmitting #{kind} with a time ignores the time" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(time_kind: kind, start_time: at("2026-11-07 18:00"))

      event.reload
      assert_equal kind, event.time_kind
      assert_equal at("2026-11-07 00:00"), event.start_time
    end

    test "moving a #{kind} event to another day without a time keeps it #{kind}" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(event_date: "2026-11-08")

      event.reload
      assert_equal kind, event.time_kind
      assert_equal at("2026-11-08 00:00"), event.start_time
    end
  end

  %w[all_day tba].each do |kind|
    test "leaving #{kind} clears the stored end" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(time_kind: "timed", start_time: at("2026-11-07 09:00"))

      event.reload
      assert_nil event.end_time
      assert_equal 0, event.hours
    end

    test "leaving #{kind} for a later day is valid when the stored end comes back from a form" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(time_kind: "timed", start_time: at("2026-11-09 09:00"), end_time: event.end_time.change(usec: 0))

      assert_nil event.reload.end_time
    end

    test "leaving #{kind} keeps a real end" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(time_kind: "timed", start_time: at("2026-11-07 09:00"), end_time: at("2026-11-07 15:00"))

      assert_equal 6.0, event.reload.hours
    end

    test "setting a real time on #{kind} without an end clears the stored end" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))

      Event.find(event.id).update!(start_time: at("2026-11-07 09:00"))

      event.reload
      assert_predicate event, :timed?
      assert_nil event.end_time
    end

    test "saving #{kind} in another zone leaves its day alone" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))
      start_time, end_time = event.reload.start_time, event.end_time

      Time.use_zone("UTC") { Event.find(event.id).update!(description: "Changed by a job") }

      event.reload
      assert_equal start_time, event.start_time
      assert_equal end_time, event.end_time
      assert_equal Date.new(2026, 11, 7), event.start_time.to_date
    end

    test "an end set alone on #{kind} is ignored, in any zone" do
      event = create_event(time_kind: kind, start_time: at("2026-11-07 14:00"))
      start_time, end_time = event.reload.start_time, event.end_time

      Time.use_zone("UTC") { Event.find(event.id).update!(end_time: nil) }

      event.reload
      assert_equal start_time, event.start_time
      assert_equal end_time, event.end_time
    end
  end

  test "upcoming keeps today's all-day and TBA events until the day ends" do
    now = at("2026-11-07 14:00")
    all_day = create_event(time_kind: "all_day", start_time: now)
    tba = create_event(time_kind: "tba", start_time: now)
    earlier = create_event(start_time: now - 1.hour, end_time: now + 1.hour)
    later = create_event(start_time: now + 1.hour)
    yesterday = create_event(time_kind: "tba", start_time: now - 1.day)

    upcoming = Event.upcoming(now)

    assert_includes upcoming, all_day
    assert_includes upcoming, tba
    assert_includes upcoming, later
    assert_not_includes upcoming, earlier
    assert_not_includes upcoming, yesterday
  end

  test "an unknown time kind is invalid rather than an exception" do
    event = build_event(time_kind: "sometime", start_time: at("2026-11-07 14:00"))

    assert_not event.valid?
    assert_predicate event.errors[:time_kind], :present?
  end

  test "combobox display shows only what is known" do
    start_time = at("2026-11-07 14:00")

    assert_equal "Meet (2026-11-07 14:00)", build_event(start_time: start_time).to_combobox_display
    assert_equal "Meet (2026-11-07)", create_event(time_kind: "all_day", start_time: start_time).to_combobox_display
    assert_equal "Meet (2026-11-07, Time TBA)", create_event(time_kind: "tba", start_time: start_time).to_combobox_display
  end

  private

  def at(string)
    Time.zone.parse(string)
  end

  def build_event(**attributes)
    Event.new(name: "Meet", event_type: event_types(:one), team: teams(:one), **attributes)
  end

  def create_event(**attributes)
    build_event(**attributes).tap(&:save!)
  end
end
