require "test_helper"

class TimeClockPeriodPolicyTest < ActiveSupport::TestCase
  setup do
    # Robotics (run by @manager)
    # └── Robotics Jr
    # Drama (unrelated)
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @robotics_jr = Team.create!(name: "Robotics Jr", team_type: team_types(:one), parent: @robotics)
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)

    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    @member = Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")
    Membership.create!(person: @member, team: @robotics)
  end

  test "managers and admins may open the new time clock period form, plain members may not" do
    assert TimeClockPeriodPolicy.new(@admin_user, TimeClockPeriod).new?
    assert TimeClockPeriodPolicy.new(@manager_user, TimeClockPeriod).new?
    assert_not TimeClockPeriodPolicy.new(@member_user, TimeClockPeriod).new?
  end

  test "an admin may create and update any time clock period" do
    [ period(@drama, "added_by_admin"), period(nil, "added_by_user") ].each do |record|
      assert TimeClockPeriodPolicy.new(@admin_user, record).create?
      assert TimeClockPeriodPolicy.new(@admin_user, record).update?
    end
  end

  test "a manager may create and update time clock periods on their team and its sub-teams only" do
    [ @robotics, @robotics_jr ].each do |team|
      assert TimeClockPeriodPolicy.new(@manager_user, period(team)).create?
      assert TimeClockPeriodPolicy.new(@manager_user, period(team)).update?
    end
    assert_not TimeClockPeriodPolicy.new(@manager_user, period(@drama)).create?
    assert_not TimeClockPeriodPolicy.new(@manager_user, period(@drama)).update?
    assert_not TimeClockPeriodPolicy.new(@manager_user, period(nil, "added_by_user")).create?
  end

  test "a manager may not create or update an admin-only time clock period" do
    assert_not TimeClockPeriodPolicy.new(@manager_user, period(@robotics, "added_by_admin")).create?
    assert_not TimeClockPeriodPolicy.new(@manager_user, period(@robotics, "added_by_admin")).update?
  end

  test "a plain member may not create a time clock period" do
    assert_not TimeClockPeriodPolicy.new(@member_user, period(@robotics, "added_by_team_member")).create?
  end

  private

  def period(team, permission = "added_by_manager")
    TimeClockPeriod.new(name: "Season", team: team, permission: permission)
  end
end
