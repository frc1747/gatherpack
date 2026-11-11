require "test_helper"

class TimeClockPunchPolicyTest < ActiveSupport::TestCase
  setup do
    # Robotics (run by @manager): @member, @classmate
    # Drama (unrelated): @outsider
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")
    @manager = create_person("manager", @robotics, manager: true)
    @member = create_person("member", @robotics)
    @classmate = create_person("classmate", @robotics)
    @outsider = create_person("outsider", @drama)
  end

  test "the empty new punch form is open to every member" do
    assert TimeClockPunchPolicy.new(@member.user, TimeClockPunch.new).new?
  end

  test "a member may record their own punches without a period and in a self-report period" do
    assert allowed?(:create?, @member, punch(@member))
    assert allowed?(:create?, @member, punch(@member, period(@robotics, "added_by_user")))
  end

  test "a member may not record punches for other people without a period or in a self-report period" do
    assert_not allowed?(:create?, @member, punch(@outsider))
    assert_not allowed?(:create?, @member, punch(@classmate))
    assert_not allowed?(:create?, @member, punch(@classmate, period(@robotics, "added_by_user")))
  end

  test "a member may record for teammates in a team member period, as before" do
    assert allowed?(:create?, @member, punch(@classmate, period(@robotics, "added_by_team_member")))
  end

  test "a member may not record in a manager or admin period" do
    assert_not allowed?(:create?, @member, punch(@member, period(@robotics, "added_by_manager")))
    assert_not allowed?(:create?, @member, punch(@member, period(@robotics, "added_by_admin")))
  end

  test "a manager may record for the people they manage, but not for others" do
    assert allowed?(:create?, @manager, punch(@member))
    assert allowed?(:create?, @manager, punch(@member, period(@robotics, "added_by_user")))
    assert allowed?(:create?, @manager, punch(@member, period(@robotics, "added_by_manager")))
    assert_not allowed?(:create?, @manager, punch(@outsider))
    assert_not allowed?(:create?, @manager, punch(@member, period(@robotics, "added_by_admin")))
  end

  test "an admin may record for anyone in any period" do
    assert TimeClockPunchPolicy.new(@admin_user, punch(@outsider)).create?
    assert TimeClockPunchPolicy.new(@admin_user, punch(@member, period(@robotics, "added_by_admin"))).create?
  end

  test "a member may update their own punch but not one handed to someone else" do
    mine = punch(@member)
    assert allowed?(:update?, @member, mine)

    mine.person = @outsider
    assert_not allowed?(:update?, @member, mine)
  end

  test "a manager may update and delete a period-less punch of a person they manage" do
    assert allowed?(:update?, @manager, punch(@member))
    assert allowed?(:destroy?, @manager, punch(@member))
    assert_not allowed?(:destroy?, @manager, punch(@outsider))
  end

  test "in team periods a manager records only for the people they manage, except in team member periods" do
    # Club (led by @leader)
    # └── Robotics (run by @manager): @member, @admin_teammate
    club = Team.create!(name: "Club", team_type: team_types(:one))
    @robotics.update!(parent: club)
    leader = create_person("leader", club, manager: true)
    admin_teammate = create_person("admin-teammate", @robotics)
    admin_teammate.user.update!(admin: true)

    %w[ added_by_admin added_by_manager added_by_user ].each do |kind|
      robotics_period = period(@robotics, kind)
      [ leader, admin_teammate ].each do |target|
        assert_not allowed?(:create?, @manager, punch(target, robotics_period)), "#{kind}: manager recorded for #{target.first_name}"
      end
      assert_equal kind != "added_by_admin", allowed?(:create?, @manager, punch(@member, robotics_period)), "#{kind}: manager for their member"
    end

    # Team members record for each other in a team member period; the manager is one of them.
    team_period = period(@robotics, "added_by_team_member")
    [ leader, admin_teammate, @member ].each do |target|
      assert allowed?(:create?, @manager, punch(target, team_period)), "added_by_team_member: manager for #{target.first_name}"
    end
    assert allowed?(:create?, @member, punch(admin_teammate, team_period))
  end

  private

  def create_person(name, team, manager: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!")
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end

  def period(team, permission)
    TimeClockPeriod.create!(name: "Season", team: team, permission: permission, start_time: 10.days.ago, end_time: 10.days.from_now)
  end

  def punch(person, period = nil)
    TimeClockPunch.new(person: person, time_clock_period: period, start_time: 2.days.ago, end_time: 2.days.ago + 3.hours)
  end

  def allowed?(action, person, record)
    TimeClockPunchPolicy.new(person.user, record).public_send(action)
  end
end
