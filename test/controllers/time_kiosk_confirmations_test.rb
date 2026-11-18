require "test_helper"

class TimeKioskConfirmationsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear

    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @period = TimeClockPeriod.create!(name: "Build Season", team: @team, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date, permission: :added_by_user)
    @member = create_person("member@example.com")
    Membership.create!(person: @member, team: @team)
    @manager = create_person("manager@example.com")
    Membership.create!(person: @manager, team: @team, manager: true)

    kiosk_user = create_person("kiosk@example.com").user
    kiosk_user.update!(kiosk: true)
    sign_in kiosk_user
  end

  teardown do
    FileUtils.rm_f(store.path)
  end

  test "clocking in says who and where, on a confirmation that fades" do
    kiosk tool: "punch_in", person_ref: ref_for(@member), time_clock_period_id: @period.id

    assert_select "#kiosk-content .alert-success[data-controller=kiosk-flash]", text: /#{@member.identifier_name} clocked in to Build Season\./
  end

  test "clocking out says who" do
    punch = open_punch(@member)

    kiosk tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id

    assert_select "#kiosk-content .alert-success", text: /#{@member.identifier_name} clocked out\./
  end

  test "a punch that is already closed gets no confirmation" do
    punch = open_punch(@member)
    punch.update!(end_time: Time.current, created_by: "kiosk")

    kiosk tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id

    assert_select "#kiosk-content .alert-success", count: 0
  end

  test "a manager's clock-out says how many people" do
    open_punch(@member)
    open_punch(@manager)

    kiosk tool: "punch_out_period", person_ref: ref_for(@manager), time_clock_period_id: @period.id
    assert_select "#kiosk-content .alert-success", text: /Clocked out 2 people from Build Season\./

    open_punch(@member)
    kiosk tool: "punch_out_all", person_ref: ref_for(@manager)
    assert_select "#kiosk-content .alert-success", text: /Clocked out 1 person\./
  end

  test "a warning doesn't fade" do
    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "999999999" } }

    assert_select "#kiosk-content .alert-warning", text: /Card not recognized/
    assert_select "[data-controller=kiosk-flash]", count: 0
  end

  test "keeping the Token box ready is off until the setting is on" do
    get time_kiosk_path
    assert_select "#kiosk-content[data-controller=kiosk-focus]", count: 0

    store.transaction { store[:time_kiosk_keep_focus] = "true" }

    get time_kiosk_path
    assert_select "#kiosk-content[data-controller=kiosk-focus]", count: 1
    assert_select "#kiosk-content input[name='time_kiosk[token_value]']", count: 1
  end

  private

  def kiosk(**params)
    post time_kiosk_path, params: { time_kiosk: params }
    assert_response :success
  end

  def ref_for(person)
    person.signed_id(purpose: :time_kiosk, expires_in: 5.minutes)
  end

  def open_punch(person)
    TimeClockPunch.create!(person: person, time_clock_period: @period, start_time: 1.hour.ago, created_by: "kiosk")
  end

  def create_person(email)
    user = User.create!(email: email, password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: email.split("@").first.capitalize)
  end

  def store
    TimeKiosk::Config.send(:store)
  end
end
