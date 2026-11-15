require "test_helper"

class TimeKiosk::AutoClockInTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 9, 18, 2)
    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @period = create_period("Build Season", @team)
    @person = Person.create!(first_name: "Test", last_name: "Member")
    Membership.create!(person: @person, team: @team)
  end

  test "periods_for lists current periods on the person's teams or on no team" do
    open_period = create_period("Open House", nil)
    create_period("Rehearsals", Team.create!(name: "Drama", team_type: team_types(:one)))
    create_period("Last Season", @team, start_time: 1.month.ago.to_date, end_time: 3.weeks.ago.to_date)

    assert_equal [ @period, open_period ].sort_by(&:id), TimeKiosk::AutoClockIn.periods_for(@person).sort_by(&:id)
  end

  test "does nothing while unassigned punches are allowed" do
    assert_no_punch_created do
      assert_nil stub_method(TimeKiosk::Config, :allow_unassigned?, true) { TimeKiosk::AutoClockIn.call(@person) }
    end
  end

  test "clocks the person in when one period applies and they have no punch in it today" do
    TimeClockPunch.create!(person: @person, time_clock_period: @period, start_time: 1.day.ago, end_time: 1.day.ago + 2.hours, created_by: "kiosk")

    result = assert_difference(-> { @person.time_clock_punches.count }) { auto_clock_in }

    punch = @person.time_clock_punches.order(:start_time).last
    assert_equal @period, result.period
    assert_equal punch, result.punch
    assert_equal @period, punch.time_clock_period
    assert_equal Time.current, punch.start_time
    assert_nil punch.end_time
    assert_equal :success, result.flash_type
    assert_equal "You're clocked in to Build Season (since 6:02 PM).", result.message
  end

  test "an open punch from today is left alone" do
    punch = TimeClockPunch.create!(person: @person, time_clock_period: @period, start_time: 1.hour.ago, created_by: "kiosk")

    result = assert_no_punch_created { auto_clock_in }

    assert_equal punch, result.punch
    assert_equal :notice, result.flash_type
    assert_equal "You're already clocked in to Build Season (since 5:02 PM).", result.message
  end

  test "a punch closed earlier today is left alone" do
    punch = TimeClockPunch.create!(person: @person, time_clock_period: @period, start_time: 3.hours.ago, end_time: 2.hours.ago, created_by: "kiosk")

    result = assert_no_punch_created { auto_clock_in }

    assert_equal punch, result.punch
    assert_equal :notice, result.flash_type
    assert_equal "You clocked out of Build Season at 4:02 PM. Use Clock In below to clock back in.", result.message
  end

  test "an open punch from an earlier day gets a warning and no new punch" do
    punch = TimeClockPunch.create!(person: @person, time_clock_period: @period, start_time: 1.day.ago, created_by: "kiosk")

    result = assert_no_punch_created { auto_clock_in }

    assert_equal punch, result.punch
    assert_equal :warning, result.flash_type
    assert_equal "You're still clocked in to Build Season from Thu, Oct 8. Clock out below, then clock in, and tell a mentor so they can fix the old punch.", result.message
  end

  test "times in banners are in the current time zone" do
    TimeClockPunch.create!(person: @person, time_clock_period: @period, start_time: 1.hour.ago, created_by: "kiosk")

    result = Time.use_zone("Eastern Time (US & Canada)") { auto_clock_in }

    assert_equal "You're already clocked in to Build Season (since 1:02 PM).", result.message
  end

  test "a punch that fails validation shows an error" do
    invalid = TimeClockPunch.new
    invalid.errors.add(:base, "invalid")

    result = stub_method(TimeClockPunch, :create, invalid) { auto_clock_in }

    assert_equal @period, result.period
    assert_nil result.punch
    assert_equal :danger, result.flash_type
    assert_equal "Couldn't clock you in. Please use the buttons below.", result.message
  end

  test "two periods mean no auto clock-in" do
    create_period("Open House", nil)

    assert_no_punch_created { assert_nil auto_clock_in }
  end

  test "no periods mean a warning and no punch" do
    @period.destroy!

    result = assert_no_punch_created { auto_clock_in }

    assert_nil result.period
    assert_equal :warning, result.flash_type
    assert_equal "No time period is open for you. See a mentor.", result.message
  end

  test "a period whose last day is today applies as it does on the profile" do
    @period.update!(end_time: Date.current)
    assert_includes TimeKiosk::AutoClockIn.periods_for(@person), @period

    result = assert_difference(-> { @person.time_clock_punches.count }) { auto_clock_in }

    assert_equal @period, result.period
    assert_equal :success, result.flash_type
  end

  private

  def auto_clock_in
    stub_method(TimeKiosk::Config, :allow_unassigned?, false) { TimeKiosk::AutoClockIn.call(@person) }
  end

  # Minitest 6 no longer ships minitest/mock.
  def stub_method(object, name, value)
    original = object.singleton_class.instance_methods(false).include?(name) && object.method(name)
    object.define_singleton_method(name) { |*, **| value }
    yield
  ensure
    original ? object.define_singleton_method(name, original) : object.singleton_class.remove_method(name)
  end

  def assert_no_punch_created(&block)
    assert_no_difference(-> { TimeClockPunch.count }, &block)
  end

  def create_period(name, team, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date)
    TimeClockPeriod.create!(name: name, team: team, start_time: start_time, end_time: end_time, permission: :added_by_user)
  end
end
