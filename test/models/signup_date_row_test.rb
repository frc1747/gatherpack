require "test_helper"

# One row of a sheet's Add dates page.
class SignupDateRowTest < ActiveSupport::TestCase
  test "a date with times becomes an event's times in the time zone" do
    Time.use_zone("Eastern Time (US & Canada)") do
      row = SignupDateRow.new(date: "2026-10-24", start_time: "10:00", end_time: "14:30", name: "", location: "Field 2")

      assert row.valid?
      attributes = row.event_attributes("Snack Stand")
      assert_equal "Snack Stand", attributes[:name]
      assert_equal "Field 2", attributes[:location]
      assert_equal Time.zone.parse("2026-10-24 10:00"), attributes[:start_time]
      assert_equal Time.zone.parse("2026-10-24 14:30"), attributes[:end_time]
      assert_equal "-04:00", attributes[:start_time].formatted_offset
    end
  end

  test "a date with no times runs 00:00 to 23:59 until its time is known" do
    attributes = SignupDateRow.new(date: "2026-11-07", name: "Picnic").event_attributes

    assert_equal [ Time.zone.parse("2026-11-07 00:00"), Time.zone.parse("2026-11-07 23:59") ], attributes.values_at(:start_time, :end_time)
    assert_equal "Picnic", attributes[:name]
  end

  test "a start time with no end leaves the end open" do
    attributes = SignupDateRow.new(date: "2026-11-07", start_time: "09:00").event_attributes

    assert_nil attributes[:end_time]
  end

  test "dates and times are checked" do
    assert_includes SignupDateRow.new(name: "Picnic").tap(&:validate).errors[:date], "is needed"
    assert_includes SignupDateRow.new(date: "2026-02-30").tap(&:validate).errors[:date], "isn't a date"
    assert_includes SignupDateRow.new(date: "2026-11-07", start_time: "25:00").tap(&:validate).errors[:start_time], "isn't a time"
    assert_includes SignupDateRow.new(date: "2026-11-07", end_time: "12:00").tap(&:validate).errors[:start_time], "is needed with an end time"
  end

  test "an empty row is skipped" do
    assert SignupDateRow.new.empty?
    assert_not SignupDateRow.new(location: "Gym").empty?
  end

  test "a row from an event shows no times while it runs 00:00 to 23:59" do
    event = Event.new(name: "Picnic", start_time: Time.zone.parse("2026-11-07 00:00"), end_time: Time.zone.parse("2026-11-07 23:59"))
    row = SignupDateRow.from_event(event)
    assert_equal [ "2026-11-07", nil, nil, "Picnic" ], [ row.date, row.start_time, row.end_time, row.name ]

    event.start_time = Time.zone.parse("2026-11-07 11:00")
    event.end_time = Time.zone.parse("2026-11-07 15:00")
    row = SignupDateRow.from_event(event)
    assert_equal [ "11:00", "15:00" ], [ row.start_time, row.end_time ]
  end
end
