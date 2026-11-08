require "test_helper"

class TimeClockPunchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    # Robotics (run by @manager): @student, @classmate
    # Drama (unrelated): @outsider
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))
    @manager = create_person("manager", @robotics, manager: true)
    @student = create_person("student", @robotics)
    @classmate = create_person("classmate", @robotics)
    @outsider = create_person("outsider", @drama)
    @admin = create_person("admin", @drama, admin: true)
    @self_report = TimeClockPeriod.create!(name: "Build season", team: @robotics, permission: :added_by_user,
                                           start_time: 10.days.ago, end_time: 10.days.from_now)
  end

  test "a member records their own punch without a period" do
    sign_in @student.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@student) }

    assert_redirected_to time_clock_punches_path
    assert TimeClockPunch.exists?(person: @student)
  end

  test "a member records their own punch in a self-report period" do
    sign_in @student.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@student, @self_report) }

    assert TimeClockPunch.exists?(person: @student, time_clock_period: @self_report)
  end

  test "a member cannot record hours for a member of another team" do
    sign_in @student.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@outsider).merge(end_time: 2.days.ago + 11.hours) }

    assert_not TimeClockPunch.exists?(person: @outsider), "student created an 11-hour punch for a Drama member"
  end

  test "a member cannot record hours for a classmate in a self-report period" do
    sign_in @student.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@classmate, @self_report) }

    assert_not TimeClockPunch.exists?(person: @classmate, time_clock_period: @self_report),
      "student created a punch for a classmate in the self-report period"
  end

  test "a member cannot hand their own punch to someone else" do
    punch = TimeClockPunch.create!(person: @student, start_time: 1.day.ago, end_time: 1.day.ago + 4.hours, created_by: @student)
    sign_in @student.user

    patch time_clock_punch_path(punch), params: { time_clock_punch: { person_id: @outsider.id } }

    assert_equal @student.id, punch.reload.person_id, "student moved their punch onto a Drama member"
  end

  test "a manager cannot move a punch onto an admin on their team" do
    admin_teammate = create_person("admin-teammate", @robotics, admin: true)
    punch = TimeClockPunch.create!(person: @student, start_time: 1.day.ago, end_time: 1.day.ago + 4.hours, created_by: @manager)
    sign_in @manager.user

    patch time_clock_punch_path(punch), params: { time_clock_punch: { person_id: admin_teammate.id } }

    assert_equal @student.id, punch.reload.person_id, "manager moved a student's punch onto an admin"
  end

  test "a manager cannot move a team period punch onto the leader of the parent team" do
    club = Team.create!(name: "Club", team_type: team_types(:one))
    @robotics.update!(parent: club)
    leader = create_person("leader", club, manager: true)
    manager_period = TimeClockPeriod.create!(name: "Pit crew", team: @robotics, permission: :added_by_manager,
                                             start_time: 10.days.ago, end_time: 10.days.from_now)
    punch = TimeClockPunch.create!(person: @student, time_clock_period: manager_period,
                                   start_time: 1.day.ago, end_time: 1.day.ago + 4.hours, created_by: @manager)
    sign_in @manager.user

    patch time_clock_punch_path(punch), params: { time_clock_punch: { person_id: leader.id } }

    assert_equal @student.id, punch.reload.person_id, "manager moved a team period punch onto the parent team's leader"
  end

  test "a member still edits the times on their own punch" do
    punch = TimeClockPunch.create!(person: @student, start_time: 1.day.ago, end_time: 1.day.ago + 4.hours, created_by: @student)
    sign_in @student.user

    patch time_clock_punch_path(punch), params: { time_clock_punch: { end_time: 1.day.ago + 2.hours } }

    assert_redirected_to time_clock_punches_path
    assert_in_delta 2.0, punch.reload.hours, 0.1
  end

  test "a manager records a punch for a member of their team" do
    sign_in @manager.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@student, @self_report) }

    assert TimeClockPunch.exists?(person: @student, time_clock_period: @self_report)
  end

  test "a manager cannot record a punch for someone outside their teams" do
    sign_in @manager.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@outsider) }

    assert_not TimeClockPunch.exists?(person: @outsider)
  end

  test "an admin records a punch for anyone" do
    sign_in @admin.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@outsider) }

    assert TimeClockPunch.exists?(person: @outsider)
  end

  test "a manager cannot bulk-delete punches they may not delete one by one" do
    punch = admin_recorded_punch
    sign_in @manager.user
    assert_not TimeClockPunchPolicy.new(@manager.user, punch).destroy?, "precondition: per-punch destroy is denied"

    delete bulk_destroy_time_clock_punches_path(violation: "too_long")

    assert TimeClockPunch.exists?(punch.id), "manager bulk-deleted a 14-hour punch in an admin-only period"
    assert_equal "Deleted 0 punches.", flash[:notice]
  end

  test "a manager bulk-deletes the flagged punches they may delete and is told how many" do
    keep = admin_recorded_punch
    gone = TimeClockPunch.create!(person: @student, start_time: 5.days.ago, end_time: 5.days.ago + 14.hours, created_by: @manager)
    sign_in @manager.user

    delete bulk_destroy_time_clock_punches_path(violation: "too_long")

    assert_not TimeClockPunch.exists?(gone.id)
    assert TimeClockPunch.exists?(keep.id)
    assert_equal "Deleted 1 punch.", flash[:notice]
  end

  test "a classmate's overlapping punch does not get a student's admin-recorded punch bulk-deleted" do
    punch = admin_recorded_punch
    sign_in @classmate.user
    post time_clock_punches_path, params: { time_clock_punch: { person_id: @student.id, start_time: 2.days.ago + 1.hour, end_time: 2.days.ago + 2.hours } }
    sign_out :user

    sign_in @manager.user
    delete bulk_destroy_time_clock_punches_path(violation: "near_duplicates")

    assert TimeClockPunch.exists?(punch.id), "a classmate's overlap got the student's admin-recorded punch deleted in a manager's bulk clean-up"
  end

  test "a classmate's overlapping punch in a team member period does not get a student's earlier punch bulk-deleted" do
    team_period = TimeClockPeriod.create!(name: "Shop nights", team: @robotics, permission: :added_by_team_member,
                                          start_time: 10.days.ago, end_time: 10.days.from_now)
    genuine = TimeClockPunch.create!(person: @student, start_time: 2.days.ago, end_time: 2.days.ago + 3.hours, created_by: @student)
    sign_in @classmate.user
    post time_clock_punches_path, params: { time_clock_punch: punch_params(@student, team_period).merge(start_time: 2.days.ago + 1.hour) }
    planted = TimeClockPunch.find_by!(person: @student, time_clock_period: team_period)
    sign_out :user

    sign_in @manager.user
    delete bulk_destroy_time_clock_punches_path(violation: "near_duplicates")

    assert TimeClockPunch.exists?(genuine.id), "the student's genuine punch was deleted with the overlap"
    assert_not TimeClockPunch.exists?(planted.id)
    assert_equal "Deleted 1 punch.", flash[:notice]
  end

  test "a short punch recorded first over a student's shift does not get the shift bulk-deleted" do
    team_period = TimeClockPeriod.create!(name: "Shop nights", team: @robotics, permission: :added_by_team_member,
                                          start_time: 10.days.ago, end_time: 10.days.from_now)
    shift_start = 1.day.from_now.change(hour: 15)
    sign_in @classmate.user
    post time_clock_punches_path, params: { time_clock_punch: { person_id: @student.id, time_clock_period_id: team_period.id,
                                                                 start_time: shift_start, end_time: shift_start + 5.minutes } }
    planted = TimeClockPunch.find_by!(person: @student, time_clock_period: team_period)
    sign_out :user
    sign_in @student.user
    post time_clock_punches_path, params: { time_clock_punch: { person_id: @student.id, start_time: shift_start, end_time: shift_start + 3.hours } }
    genuine = TimeClockPunch.find_by!(person: @student, time_clock_period: nil)
    sign_out :user

    sign_in @manager.user
    delete bulk_destroy_time_clock_punches_path(violation: "near_duplicates")

    assert TimeClockPunch.exists?(genuine.id), "the student's 3-hour shift was deleted in favour of a 5-minute punch recorded first"
    assert_not TimeClockPunch.exists?(planted.id)
  end

  test "the flag review offers bulk delete only for punches the user may delete" do
    admin_recorded_punch
    sign_in @manager.user

    get flagged_time_clock_punches_path

    assert_response :success
    assert_no_match bulk_destroy_time_clock_punches_path(violation: "too_long"), response.body

    sign_out :user
    sign_in @admin.user
    get flagged_time_clock_punches_path

    assert_match bulk_destroy_time_clock_punches_path(violation: "too_long"), response.body
  end

  private

  def admin_recorded_punch
    admin_only = TimeClockPeriod.create!(name: "Competition travel", team: @robotics, permission: :added_by_admin,
                                         start_time: 10.days.ago, end_time: 10.days.from_now)
    TimeClockPunch.create!(person: @student, time_clock_period: admin_only,
                           start_time: 2.days.ago, end_time: 2.days.ago + 14.hours, created_by: @admin)
  end

  def create_person(name, team, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end

  def punch_params(person, period = nil)
    { person_id: person.id, time_clock_period_id: period&.id, start_time: 2.days.ago, end_time: 2.days.ago + 3.hours }
  end
end
