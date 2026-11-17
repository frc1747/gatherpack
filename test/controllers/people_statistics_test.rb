require "test_helper"

# A person's statistics page counts only the punches, events and periods the
# viewer may see.
class PeopleStatisticsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    # Pack (Pack event)
    # ├── Den A: @student
    # └── Den B: @classmate, @den_b_leader (manager); Den B period and event
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack)
    @student = create_person("student", @den_a)
    @classmate = create_person("classmate", @den_b)
    @den_b_leader = create_person("den-b-leader", @den_b, manager: true)
    @admin = create_person("admin", @den_a, admin: true)

    @period = TimeClockPeriod.create!(name: "Den B season", team: @den_b, start_time: 1.month.ago, end_time: 1.month.from_now)
    TimeClockPunch.create!(person: @classmate, time_clock_period: @period, created_by: "kiosk", start_time: 2.days.ago, end_time: 2.days.ago + 7.hours)
    pack_event = Event.create!(name: "Pack meeting", start_time: 3.days.ago, event_type: event_types(:one), team: @pack)
    den_b_event = Event.create!(name: "Den B meeting", start_time: 3.days.ago, event_type: event_types(:one), team: @den_b, time_clock_period: @period)
    Checkin.create!(event: pack_event, person: @classmate)
    Checkin.create!(event: den_b_event, person: @classmate)
  end

  test "a member can't see another team's member's attendance hours" do
    sign_in @student.user

    get statistics_person_path(@classmate)

    assert_response :success
    assert_no_match(/Punched in/, response.body)
  end

  test "a member counts only the check-ins at events they may see" do
    sign_in @student.user

    get statistics_person_path(@classmate)

    assert_match(/Checked in 1 event</, response.body)
    assert_no_match(/Den B season/, response.body)
  end

  test "the person, their manager and an admin see the real totals" do
    [ @classmate, @den_b_leader, @admin ].each do |viewer|
      sign_in viewer.user

      get statistics_person_path(@classmate)

      assert_match(/Punched in 7.0 hours</, response.body, "#{viewer.first_name} didn't see the hours")
      assert_match(/Checked in 2 events</, response.body, "#{viewer.first_name} didn't see every check-in")
      assert_match(/Punched in 7.0 hours in this period/, response.body, "#{viewer.first_name} didn't see the period's hours")
      assert_match(/Checked in 1 event from this period/, response.body, "#{viewer.first_name} didn't see the period's check-ins")
    end
  end

  test "a person with no punches sees zero hours on their own page" do
    sign_in @student.user

    get statistics_person_path(@student)

    assert_match(/Punched in 0(\.0)? hours/, response.body)
  end

  private

  def create_person(name, team, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end
end
