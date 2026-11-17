require "test_helper"

class TimeKioskAutoClockInTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear
    travel_to Time.utc(2026, 10, 9, 18, 2)

    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @period = create_period("Build Season", @team)

    @member = create_person("member@example.com")
    Membership.create!(person: @member, team: @team)
    @member_token = Token.create!(value: "100000001", tokenable: @member)

    sign_in create_person("kiosk@example.com").user
  end

  test "with unassigned off and one period, a scan clocks the person in once" do
    without_unassigned do
      assert_difference -> { @member.time_clock_punches.count } do
        scan
      end
      assert_select ".alert-success", text: /You're clocked in to Build Season/
      assert_select "h3", text: "Open Punches"

      assert_no_punch_created { scan }
      assert_select ".alert-info", text: /You're already clocked in to Build Season/
    end

    punch = @member.time_clock_punches.sole
    assert_equal @period, punch.time_clock_period
    assert_nil punch.end_time
  end

  test "with unassigned off and one period, a scan over GET clocks no one in" do
    without_unassigned do
      assert_no_punch_created do
        get time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: @member_token.value } }
      end
    end

    assert_response :success
    assert_select "h3", text: @member.identifier_name
    assert_select "a", text: /Build Season/
    assert_select ".alert", count: 0
  end

  test "with unassigned off, a scan after clocking out today creates nothing" do
    TimeClockPunch.create!(person: @member, time_clock_period: @period, start_time: 2.hours.ago, end_time: 1.hour.ago, created_by: "kiosk")

    without_unassigned do
      assert_no_punch_created { scan }
    end

    assert_select ".alert-info", text: /You clocked out of Build Season at .* Use Clock In below to clock back in/
    assert_select "a", text: /Build Season/
  end

  test "with unassigned off, a scan with yesterday's punch still open creates nothing and warns" do
    TimeClockPunch.create!(person: @member, time_clock_period: @period, start_time: 1.day.ago, created_by: "kiosk")

    without_unassigned do
      assert_no_punch_created { scan }
    end

    assert_select ".alert-warning", text: /You're still clocked in to Build Season from .* tell a mentor/
  end

  test "with unassigned off, Start Unassigned is hidden and punch_in without a period is refused" do
    create_period("Open House", nil)

    without_unassigned do
      assert_no_punch_created { scan }
      assert_select "h3", text: @member.identifier_name
      assert_select "a", text: /Build Season/
      assert_select "a", text: /Open House/
      assert_select "a", text: /Start Unassigned/, count: 0

      assert_no_punch_created { kiosk tool: "punch_in", person_ref: ref_for(@member), time_clock_period_id: nil }
    end

    assert_select "h2", text: "Welcome to the Time Kiosk"
    assert_select ".alert-warning", text: /Choose a time period/
  end

  test "with unassigned off and no period, the profile says so" do
    @period.destroy!

    without_unassigned do
      assert_no_punch_created { scan }
    end

    assert_select "h3", text: @member.identifier_name
    assert_select ".alert-warning", text: /No time period is open for you. See a mentor./
    assert_select "a[data-turbo-method=post]", text: /Start Unassigned/, count: 0
  end

  test "with unassigned allowed, the kiosk behaves as before" do
    stub_method(TimeKiosk::Config, :allow_unassigned?, true) do
      assert_no_punch_created { scan }
      assert_select "a", text: /Start Unassigned/
      assert_select "a", text: /Build Season/
      assert_select ".alert", count: 0

      assert_no_punch_created { kiosk tool: "punch_in", person_ref: ref_for(@member), time_clock_period_id: nil }
      assert_select ".alert", text: /Choose a time period/, count: 0
    end
  end

  test "an unknown card shows Welcome with a banner and creates no punch" do
    assert_no_punch_created { kiosk tool: "find_token", token_value: "999999999" }

    assert_response :success
    assert_select "h2", text: "Welcome to the Time Kiosk"
    assert_select ".alert-warning", text: /Card not recognized. Try again or see a mentor./
  end

  test "a token with no person shows the same banner" do
    token = Token.create!(value: "200000002", tokenable: hooks(:one))

    assert_no_punch_created { kiosk tool: "find_token", token_value: token.value }

    assert_select "h2", text: "Welcome to the Time Kiosk"
    assert_select ".alert-warning", text: /Card not recognized. Try again or see a mentor./
  end

  test "a blank submission shows Welcome without the banner" do
    kiosk tool: "find_token", token_value: ""

    assert_select "h2", text: "Welcome to the Time Kiosk"
    assert_select ".alert", count: 0
  end

  test "the button says Clock In when unassigned is off and Search by default" do
    without_unassigned do
      get time_kiosk_path
      assert_select "input[type=submit][value='Clock In']"
    end

    get time_kiosk_path
    assert_select "input[type=submit][value=Search]"
  end

  private

  def scan
    kiosk tool: "find_token", token_value: @member_token.value
    assert_response :success
  end

  def kiosk(**params)
    post time_kiosk_path, params: { time_kiosk: params }
  end

  def without_unassigned(&block)
    stub_method(TimeKiosk::Config, :allow_unassigned?, false, &block)
  end

  # Minitest 6 no longer ships minitest/mock.
  def stub_method(object, name, value)
    original = object.singleton_class.instance_methods(false).include?(name) && object.method(name)
    object.define_singleton_method(name) { |*, **| value }
    yield
  ensure
    original ? object.define_singleton_method(name, original) : object.singleton_class.remove_method(name)
  end

  def ref_for(person)
    person.signed_id(purpose: :time_kiosk, expires_in: 5.minutes)
  end

  def assert_no_punch_created(&block)
    assert_no_difference(-> { TimeClockPunch.count }, &block)
  end

  def create_period(name, team, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date)
    TimeClockPeriod.create!(name: name, team: team, start_time: start_time, end_time: end_time, permission: :added_by_user)
  end

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end
end
