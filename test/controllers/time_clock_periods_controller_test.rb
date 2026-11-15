require "test_helper"

class TimeClockPeriodsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

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

    @period = TimeClockPeriod.create!(name: "Build season", team: @robotics, permission: "added_by_manager",
                                      start_time: 1.day.ago, end_time: 1.day.from_now)
  end

  # --- create -------------------------------------------------------------

  test "a manager cannot create a time clock period on a team they don't manage" do
    sign_in @manager_user

    post time_clock_periods_path, params: { time_clock_period: period_params(name: "Rehearsals", team_id: @drama.id) }

    assert_not TimeClockPeriod.exists?(name: "Rehearsals"), "manager of Robotics created a time clock period on the Drama team"
    assert_redirected_to root_path
  end

  test "a manager cannot create an admin-only time clock period" do
    sign_in @manager_user

    post time_clock_periods_path, params: { time_clock_period: period_params(name: "Off season", team_id: @robotics.id, permission: "added_by_admin") }

    assert_not TimeClockPeriod.exists?(name: "Off season"), "manager of Robotics created an admin-only time clock period"
    assert_redirected_to root_path
  end

  test "a manager can create a time clock period on their team and its sub-teams" do
    sign_in @manager_user

    [ @robotics, @robotics_jr ].each do |team|
      post time_clock_periods_path, params: { time_clock_period: period_params(name: "#{team.name} season", team_id: team.id) }

      assert_redirected_to time_clock_period_path(TimeClockPeriod.find_by!(name: "#{team.name} season", team: team))
    end
  end

  test "an admin can create an admin-only time clock period on any team" do
    sign_in @admin_user

    post time_clock_periods_path, params: { time_clock_period: period_params(name: "Rehearsals", team_id: @drama.id, permission: "added_by_admin") }

    period = TimeClockPeriod.find_by!(name: "Rehearsals", team: @drama)
    assert_redirected_to time_clock_period_path(period)
    assert period.added_by_admin?
  end

  # --- update -------------------------------------------------------------

  test "a manager cannot move their time clock period to a team they don't manage" do
    sign_in @manager_user

    patch time_clock_period_path(@period), params: { time_clock_period: { team_id: @drama.id } }

    assert_equal @robotics, @period.reload.team, "manager of Robotics moved a time clock period to the Drama team"
    assert_redirected_to root_path
  end

  test "a manager cannot make their time clock period admin-only" do
    sign_in @manager_user

    patch time_clock_period_path(@period), params: { time_clock_period: { permission: "added_by_admin" } }

    assert @period.reload.added_by_manager?, "manager of Robotics made a time clock period admin-only"
    assert_redirected_to root_path
  end

  test "a manager can rename their time clock period and move it to a sub-team" do
    sign_in @manager_user

    patch time_clock_period_path(@period), params: { time_clock_period: { name: "Robotics Jr season", team_id: @robotics_jr.id } }

    assert_redirected_to time_clock_period_path(@period)
    assert_equal "Robotics Jr season", @period.reload.name
    assert_equal @robotics_jr, @period.team
  end

  test "an admin can move a time clock period to any team and make it admin-only" do
    sign_in @admin_user

    patch time_clock_period_path(@period), params: { time_clock_period: { team_id: @drama.id, permission: "added_by_admin" } }

    assert_redirected_to time_clock_period_path(@period)
    assert_equal @drama, @period.reload.team
    assert @period.added_by_admin?
  end

  private

  def period_params(**attributes)
    { permission: "added_by_manager", start_time: 1.day.ago, end_time: 1.day.from_now }.merge(attributes)
  end
end
