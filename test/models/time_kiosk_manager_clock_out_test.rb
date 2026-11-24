require "test_helper"
require_relative "../support/settings_test_helper"

class TimeKioskManagerClockOutTest < ActiveSupport::TestCase
  include SettingsTestHelper

  setup do
    type = team_types(:one)
    @club = Team.create!(name: "Club", team_type: type)
    @coaches = Team.create!(name: "Coaches", team_type: type, parent_id: @club.id)
    @juniors = Team.create!(name: "Juniors", team_type: type, parent_id: @coaches.id)
    @season = TimeClockPeriod.create!(name: "Season", team: @club, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date, permission: :added_by_admin)

    @coach = person("Coach", @coaches, manager: true)
    @junior = person("Junior", @juniors)
    @outsider = person("Outsider", @club)
    @punches = [ @coach, @junior, @outsider ].to_h { |p| [ p, open_punch(p, @season) ] }
  end

  test "off: a manager of a team below the period's team has nothing to clock out" do
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "false") do
      clock_out = TimeKiosk::ManagerClockOut.new(@coach)
      assert_not clock_out.anything?
      assert_nil clock_out.clock_out_period!(@season)
      assert_nil clock_out.clock_out_all!
    end
    assert @punches.values.all? { |punch| punch.reload.end_time.nil? }
  end

  test "on: a manager clocks out the people they manage, including teams below, and no one else" do
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "true") do
      clock_out = TimeKiosk::ManagerClockOut.new(@coach)
      assert_equal [ @season ], clock_out.groups.map(&:period)
      assert_equal [ @coach, @junior ].sort_by(&:id), clock_out.groups.first.punches.map(&:person).sort_by(&:id)

      assert_equal 2, clock_out.clock_out_period!(@season)
    end
    assert @punches[@coach].reload.end_time
    assert @punches[@junior].reload.end_time
    assert_nil @punches[@outsider].reload.end_time
  end

  test "on: punches with no period get their own row and can be clocked out" do
    unassigned = open_punch(@junior, nil)
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "true") do
      clock_out = TimeKiosk::ManagerClockOut.new(@coach)
      assert_equal [ @season, nil ], clock_out.groups.map(&:period)
      assert_equal 1, clock_out.clock_out_period!(nil)
      assert_equal 2, clock_out.clock_out_all!
    end
    assert unassigned.reload.end_time
    assert_nil @punches[@outsider].reload.end_time
  end

  test "a manager of the period's team clocks out everyone in it, with the setting on or off" do
    top = person("Top", @club, manager: true)
    %w[ false true ].each do |value|
      with_settings(TimeKiosk::ManagerClockOut::SETTING => value) do
        TimeClockPunch.where(id: @punches.values.map(&:id)).update_all(end_time: nil)
        assert_equal 3, TimeKiosk::ManagerClockOut.new(top).clock_out_all!
      end
    end
  end

  test "a manager with no login can't clock anyone out" do
    no_login = Person.create!(first_name: "No", last_name: "Login")
    Membership.create!(person: no_login, team: @club, manager: true)
    with_settings(TimeKiosk::ManagerClockOut::SETTING => "true") do
      assert_not TimeKiosk::ManagerClockOut.new(no_login).anything?
    end
  end

  private

  def person(first, team, manager: false)
    user = User.create!(email: "#{first.downcase}@example.com", password: "Password1!")
    Person.create!(user: user, first_name: first, last_name: "Test").tap do |p|
      Membership.create!(person: p, team: team, manager: manager)
    end
  end

  def open_punch(person, period)
    TimeClockPunch.create!(person: person, time_clock_period: period, start_time: 1.hour.ago, created_by: "kiosk")
  end
end
