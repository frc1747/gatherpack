require "test_helper"

class TimeKioskControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @period = TimeClockPeriod.create!(name: "Build Season", team: @team, start_time: 1.week.ago, end_time: 1.week.from_now)
    @member_user, @member = create_person("member", team: @team)
    _, @teammate = create_person("teammate", team: @team)
    Token.create!(value: "8675309", tokenable: @teammate)
    @admin_user, = create_person("admin", admin: true)
  end

  test "a card scanned in the 5700 reader format finds its holder" do
    sign_in @admin_user

    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "5700" + 8675309.to_s(16) } }

    assert_response :success
    assert_select "h2", "Found Person"
    assert_select "h3", @teammate.identifier_name
  end

  # --- who may run the kiosk ----------------------------------------------

  test "a member's own session cannot scan a teammate's card and clock them in" do
    sign_in @member_user

    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: "8675309" } }
    button = kiosk_buttons.find { |b| b["tool"] == "punch_in" && b["time_clock_period_id"].present? }
    post time_kiosk_path, params: { time_kiosk: button } if button

    assert_not @teammate.time_clock_punches.exists?,
      "a member's own account scanned a teammate's card and clocked them in"
  end

  test "a member's own session cannot clock someone in by their person id" do
    sign_in @member_user

    post time_kiosk_path, params: { time_kiosk: { tool: "punch_in", person_id: @teammate.id, time_clock_period_id: @period.id } }

    assert_not @teammate.time_clock_punches.exists?,
      "a member's own account clocked a teammate in by posting their person id"
  end

  test "an account that isn't a kiosk account is told so" do
    sign_in @member_user

    get time_kiosk_path

    assert_response :forbidden
    assert_select ".alert", /This account can't run the time kiosk; an admin can make it a kiosk account/
    assert_select "form#new_time_kiosk", count: 0
  end

  test "an admin can run the kiosk" do
    sign_in @admin_user

    scan "8675309"
    post time_kiosk_path, params: { time_kiosk: button("punch_in") }

    assert @teammate.time_clock_punches.where(time_clock_period: @period, end_time: nil).exists?
  end

  # --- what a kiosk account can do ----------------------------------------

  test "a kiosk account clocks the scanned person in and out" do
    sign_in kiosk_user

    scan "8675309"
    assert_select "h3", @teammate.identifier_name
    post time_kiosk_path, params: { time_kiosk: button("punch_in") }

    punch = @teammate.time_clock_punches.sole
    assert_equal @period, punch.time_clock_period
    assert_nil punch.end_time

    scan "8675309"
    post time_kiosk_path, params: { time_kiosk: button("punch_out") }

    assert_not_nil punch.reload.end_time
  end

  test "the clock-in buttons carry a signed reference, not a person id" do
    sign_in kiosk_user

    scan "8675309"

    assert kiosk_buttons.any?
    kiosk_buttons.each do |b|
      assert_nil b["person_id"]
      assert b["person_ref"].present?
    end
  end

  test "a punch with no reference, only a person id, is refused" do
    sign_in kiosk_user

    post time_kiosk_path, params: { time_kiosk: { tool: "punch_in", person_id: @teammate.id, time_clock_period_id: @period.id } }

    assert_not @teammate.time_clock_punches.exists?
    assert_select ".alert", /scan your card again/
  end

  test "a forged reference is refused" do
    sign_in kiosk_user

    scan "8675309"
    punch_in = button("punch_in")
    ref = punch_in["person_ref"]
    forged = punch_in.merge("person_ref" => Rails.application.message_verifier(:other).generate(@member.id))
    post time_kiosk_path, params: { time_kiosk: forged }
    tampered = punch_in.merge("person_ref" => ref.chop + (ref.end_with?("a") ? "b" : "a"))
    post time_kiosk_path, params: { time_kiosk: tampered }

    assert_not @member.time_clock_punches.exists?
    assert_not @teammate.time_clock_punches.exists?
  end

  test "a reference stops working after a few minutes" do
    sign_in kiosk_user

    scan "8675309"
    punch_in = button("punch_in")
    travel 10.minutes
    post time_kiosk_path, params: { time_kiosk: punch_in }

    assert_not @teammate.time_clock_punches.exists?
    assert_select ".alert", /scan your card again/
  end

  test "a kiosk account can't clock the scanned person out of someone else's punch" do
    other_punch = TimeClockPunch.create!(person: @member, start_time: 1.hour.ago, time_clock_period: @period, created_by: "kiosk")
    sign_in kiosk_user

    scan "8675309"
    post time_kiosk_path, params: { time_kiosk: { tool: "punch_out", person_ref: button("punch_in")["person_ref"], time_clock_punch_id: other_punch.id } }

    assert_nil other_punch.reload.end_time
  end

  test "a kiosk account can't clock the scanned person into a period they weren't offered" do
    other_team = Team.create!(name: "Drama", team_type: team_types(:one))
    other_period = TimeClockPeriod.create!(name: "Rehearsals", team: other_team, start_time: 1.week.ago, end_time: 1.week.from_now)
    sign_in kiosk_user

    scan "8675309"
    post time_kiosk_path, params: { time_kiosk: button("punch_in").merge("time_clock_period_id" => other_period.id) }

    assert_not @teammate.time_clock_punches.exists?
  end

  test "a scanned manager clocks out everyone in their period" do
    @period.update!(permission: :added_by_manager)
    _, manager = create_person("manager", team: @team, manager: true)
    Token.create!(value: "4242", tokenable: manager)
    punch = TimeClockPunch.create!(person: @teammate, start_time: 1.hour.ago, time_clock_period: @period, created_by: "kiosk")
    sign_in kiosk_user

    scan "4242"
    post time_kiosk_path, params: { time_kiosk: button("punch_out_period") }

    assert_not_nil punch.reload.end_time
  end

  test "a scanned member who manages nothing can't clock out a period" do
    @period.update!(permission: :added_by_manager)
    punch = TimeClockPunch.create!(person: @member, start_time: 1.hour.ago, time_clock_period: @period, created_by: "kiosk")
    sign_in kiosk_user

    scan "8675309"
    ref = button("punch_in")["person_ref"]
    post time_kiosk_path, params: { time_kiosk: { tool: "punch_out_period", person_ref: ref, time_clock_period_id: @period.id } }
    post time_kiosk_path, params: { time_kiosk: { tool: "punch_out_all", person_ref: ref } }

    assert_nil punch.reload.end_time
  end

  test "the kiosk renders only its own pages" do
    sign_in kiosk_user

    [ "layouts/sidebar", "kiosk", "found_person", "found_hook" ].each do |tool|
      get time_kiosk_path, params: { time_kiosk: { tool: tool } }
      assert_response :success, tool
      assert_select "h2", "Welcome to the Time Kiosk"
    end
  end

  test "a card held by a hook shows the card as not found" do
    hook = Hook.create!(name: "Door", event: "tokens - create", code: "nil")
    Token.create!(value: "1234", tokenable: hook)
    sign_in kiosk_user

    scan "1234"

    assert_select ".card-body", /Token not found/
  end

  test "following a punch button with a GET doesn't punch" do
    sign_in kiosk_user

    scan "8675309"
    get time_kiosk_path, params: { time_kiosk: button("punch_in") }

    assert_response :success
    assert_not @teammate.time_clock_punches.exists?
  end

  private

  def kiosk_user
    user, = create_person("kiosk")
    user.update!(kiosk: true)
    user
  end

  def scan(value)
    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: value } }
    assert_response :success
  end

  # The time_kiosk params of each POST button on the page.
  def kiosk_buttons
    css_select("a[data-turbo-method=post]").map do |a|
      Rack::Utils.parse_nested_query(URI(a["href"]).query)["time_kiosk"]
    end
  end

  def button(tool)
    kiosk_buttons.find { |b| b["tool"] == tool && (tool != "punch_in" || b["time_clock_period_id"].present?) } ||
      flunk("no #{tool} button on the page")
  end

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
