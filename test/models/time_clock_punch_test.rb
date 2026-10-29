require "test_helper"

class TimeClockPunchTest < ActiveSupport::TestCase
  setup do
    # Robotics (run by @manager): @member, @classmate
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @manager = create_person("manager", manager: true)
    @member = create_person("member")
    @classmate = create_person("classmate")
    @self_report = TimeClockPeriod.create!(name: "Build season", team: @robotics, permission: :added_by_user,
                                           start_time: 10.days.ago, end_time: 10.days.from_now)
  end

  test "a member's own punch is valid without a period and in a self-report period" do
    assert punch(@member, created_by: @member).valid?
    assert punch(@member, @self_report, created_by: @member).valid?
  end

  test "a punch recorded by a member for someone else is invalid" do
    assert_not punch(@classmate, created_by: @member).valid?
    assert_not punch(@classmate, @self_report, created_by: @member).valid?
  end

  test "a punch recorded by the person's manager is valid" do
    assert punch(@member, created_by: @manager).valid?
    assert punch(@member, @self_report, created_by: @manager).valid?
  end

  test "a kiosk punch is valid for whoever clocked in" do
    assert punch(@member, @self_report, created_by: "kiosk").valid?
    assert TimeClockPunch.create(person: @member, time_clock_period: @self_report, start_time: Time.current, created_by: "kiosk").persisted?
  end

  private

  def create_person(name, manager: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!")
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: @robotics, manager: manager)
    person
  end

  def punch(person, period = nil, created_by:)
    TimeClockPunch.new(person: person, time_clock_period: period, start_time: 2.days.ago, end_time: 2.days.ago + 3.hours, created_by: created_by)
  end
end
