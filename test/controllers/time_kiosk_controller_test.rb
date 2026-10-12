require "test_helper"

class TimeKioskControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear

    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @other_team = Team.create!(name: "Drama", team_type: team_types(:one))
    @period = create_period("Build Season", @team)
    @other_period = create_period("Rehearsals", @other_team)

    @member = create_person("member@example.com")
    Membership.create!(person: @member, team: @team)
    @member_token = Token.create!(value: "100000001", tokenable: @member)

    @manager = create_person("manager@example.com")
    Membership.create!(person: @manager, team: @team, manager: true)

    sign_in create_person("kiosk@example.com").user
  end

  test "a scan shows the profile with buttons that carry a person reference" do
    Membership.create!(person: @member, team: @other_team, manager: true)
    create_period("Workshops", @other_team)
    TimeClockPunch.create!(person: @member, time_clock_period: @period, start_time: Time.current, created_by: "kiosk")

    kiosk tool: "find_token", token_value: @member_token.value

    assert_response :success
    assert_select "h3", text: @member.identifier_name
    hrefs = css_select("a[data-turbo-method=post]").map { |a| a["href"] }
    tools = hrefs.map { |href| kiosk_params(href)["tool"] }
    assert_equal %w[ punch_in punch_out punch_out_all punch_out_period ], tools.uniq.sort
    hrefs.each do |href|
      assert_includes href, "person_ref"
      assert_not_includes href, "person_id"
    end

    clock_in = kiosk_params(css_select("a[data-turbo-method=post]").find { |a| kiosk_params(a["href"])["tool"] == "punch_in" && a.text.include?("Rehearsals") }["href"])
    ref = clock_in["person_ref"]
    assert_equal @member, Person.find_signed(ref, purpose: :time_kiosk)
    travel 6.minutes do
      assert_nil Person.find_signed(ref, purpose: :time_kiosk)
    end

    assert_difference -> { @member.time_clock_punches.where(time_clock_period: @other_period).count } do
      kiosk tool: "punch_in", person_ref: ref, time_clock_period_id: clock_in["time_clock_period_id"]
    end
  end

  test "punch_in clocks in the scanned person" do
    assert_difference -> { @member.time_clock_punches.count } do
      kiosk tool: "punch_in", person_ref: ref_for(@member), time_clock_period_id: @period.id
    end

    punch = @member.time_clock_punches.last
    assert_equal @period, punch.time_clock_period
    assert_nil punch.end_time
  end

  test "punch_in creates nothing without a valid reference" do
    expired_ref = ref_for(@member)
    travel 6.minutes do
      assert_no_punch_created { kiosk tool: "punch_in", person_ref: expired_ref, time_clock_period_id: @period.id }
    end

    assert_no_punch_created { kiosk tool: "punch_in", person_ref: "forged", time_clock_period_id: @period.id }
    assert_no_punch_created { kiosk tool: "punch_in", person_ref: "#{ref_for(@member)}x", time_clock_period_id: @period.id }
    assert_no_punch_created { kiosk tool: "punch_in", person_ref: @member.signed_id(purpose: :other), time_clock_period_id: @period.id }
    assert_no_punch_created { kiosk tool: "punch_in", person_ref: @member.signed_id, time_clock_period_id: @period.id }
    assert_no_punch_created { kiosk tool: "punch_in", person_id: @member.id, time_clock_period_id: @period.id }

    assert_response :success
    assert_select ".alert", text: /Please scan your card again/
  end

  test "punch_in creates nothing over GET" do
    assert_no_punch_created do
      get time_kiosk_path, params: { time_kiosk: { tool: "punch_in", person_ref: ref_for(@member), person_id: @member.id, time_clock_period_id: @period.id } }
    end

    assert_response :success
    assert_select "h2", text: "Welcome to the Time Kiosk"
  end

  test "punch_in creates nothing for a period the person can't use" do
    past_period = create_period("Last Season", @team, start_time: 1.month.ago.to_date, end_time: 3.weeks.ago.to_date)

    assert_no_punch_created { kiosk tool: "punch_in", person_ref: ref_for(@member), person_id: @member.id, time_clock_period_id: @other_period.id }
    assert_no_punch_created { kiosk tool: "punch_in", person_ref: ref_for(@member), person_id: @member.id, time_clock_period_id: past_period.id }
    assert_no_punch_created { kiosk tool: "punch_in", person_ref: ref_for(@member), person_id: @member.id, time_clock_period_id: nil }
  end

  test "punch_in creates nothing when the person already has an open punch in the period" do
    TimeClockPunch.create!(person: @member, time_clock_period: @period, start_time: @period.start_time.beginning_of_day, created_by: "kiosk")

    assert_no_punch_created { kiosk tool: "punch_in", person_ref: ref_for(@member), person_id: @member.id, time_clock_period_id: @period.id }
  end

  test "punch_out clocks out the scanned person's open punch" do
    punch = open_punch(@member)

    kiosk tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id

    assert_not_nil punch.reload.end_time
  end

  test "punch_out refuses a punch belonging to someone else" do
    punch = open_punch(@manager)

    kiosk tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id

    assert_nil punch.reload.end_time
  end

  test "punch_out refuses a closed punch" do
    end_time = 1.hour.ago.change(usec: 0)
    punch = TimeClockPunch.create!(person: @member, time_clock_period: @period, start_time: 2.hours.ago, end_time: end_time, created_by: "kiosk")

    kiosk tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id

    assert_equal end_time, punch.reload.end_time
  end

  test "punch_out refuses a GET" do
    punch = open_punch(@member)

    get time_kiosk_path, params: { time_kiosk: { tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id } }

    assert_response :success
    assert_nil punch.reload.end_time
  end

  test "punch_out_period clocks out the period for a manager" do
    punch = open_punch(@member)

    kiosk tool: "punch_out_period", person_ref: ref_for(@manager), time_clock_period_id: @period.id

    assert_not_nil punch.reload.end_time
  end

  test "punch_out_period refuses a non-manager, a bare person_id and a manager with no login" do
    punch = open_punch(@member)
    no_login = create_manager_without_login

    kiosk tool: "punch_out_period", person_ref: ref_for(@member), time_clock_period_id: @period.id
    assert_response :success
    kiosk tool: "punch_out_period", person_id: @manager.id, time_clock_period_id: @period.id
    assert_response :success
    kiosk tool: "punch_out_period", person_ref: ref_for(no_login), time_clock_period_id: @period.id
    assert_response :success

    assert_nil punch.reload.end_time
  end

  test "punch_out_all clocks out every managed period for a manager" do
    punch = open_punch(@member)

    kiosk tool: "punch_out_all", person_ref: ref_for(@manager)

    assert_not_nil punch.reload.end_time
  end

  test "punch_out_all refuses a non-manager, a bare person_id and a manager with no login" do
    punch = open_punch(@member)
    no_login = create_manager_without_login

    kiosk tool: "punch_out_all", person_ref: ref_for(@member)
    assert_response :success
    kiosk tool: "punch_out_all", person_id: @manager.id
    assert_response :success
    kiosk tool: "punch_out_all", person_ref: ref_for(no_login)
    assert_response :success

    assert_nil punch.reload.end_time
  end

  test "an unknown tool renders Welcome" do
    [ "found_hook", "time_kiosk/period_select_form", "../layouts/kiosk", "found_person" ].each do |tool|
      kiosk tool: tool

      assert_response :success
      assert_select "h2", text: "Welcome to the Time Kiosk"
      assert_select ".card-body", text: /Please scan your token to begin/
    end
  end

  test "a Hook's token shows the bad card banner" do
    token = Token.create!(value: "200000002", tokenable: hooks(:one))

    kiosk tool: "find_token", token_value: token.value

    assert_response :success
    assert_select "h2", text: "Welcome to the Time Kiosk"
    assert_select ".alert-warning", text: /Card not recognized/
  end

  test "the 61st lookup in a minute from the same user is refused" do
    60.times do
      kiosk tool: "find_token", token_value: @member_token.value
      assert_select "h3", text: @member.identifier_name
    end

    kiosk tool: "find_token", token_value: @member_token.value

    assert_response :success
    assert_select "h3", text: @member.identifier_name, count: 0
    assert_select ".alert", text: /Too many scans/
  end

  test "punch tools still work after 60 lookups in a minute" do
    60.times { kiosk tool: "find_token", token_value: @member_token.value }

    assert_difference -> { @member.time_clock_punches.count } do
      kiosk tool: "punch_in", person_ref: ref_for(@member), time_clock_period_id: @period.id
    end
    assert_select ".alert", text: /Too many scans/, count: 0
  end

  private

  def kiosk(**params)
    post time_kiosk_path, params: { time_kiosk: params }
  end

  def kiosk_params(href)
    Rack::Utils.parse_nested_query(URI(href).query)["time_kiosk"]
  end

  def ref_for(person)
    person.signed_id(purpose: :time_kiosk, expires_in: 5.minutes)
  end

  def assert_no_punch_created(&block)
    assert_no_difference -> { TimeClockPunch.count }, &block
  end

  def open_punch(person)
    TimeClockPunch.create!(person: person, time_clock_period: @period, start_time: 1.hour.ago, created_by: "kiosk")
  end

  def create_period(name, team, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date)
    TimeClockPeriod.create!(name: name, team: team, start_time: start_time, end_time: end_time, permission: :added_by_user)
  end

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end

  def create_manager_without_login
    person = Person.create!(first_name: "No", last_name: "Login")
    Membership.create!(person: person, team: @team, manager: true)
    person
  end
end
