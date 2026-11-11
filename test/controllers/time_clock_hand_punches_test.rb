require "test_helper"

class TimeClockHandPunchesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  SELF_ENTRY_PERMISSIONS = %w[ added_by_user added_by_team_member ].freeze
  ALL_PERMISSIONS = (SELF_ENTRY_PERMISSIONS + %w[ added_by_manager added_by_admin ]).freeze

  setup do
    host! "localhost"
    # Robotics (run by @manager): @member, @classmate
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @manager = create_person("manager", @robotics, manager: true)
    @member = create_person("member", @robotics)
    @classmate = create_person("classmate", @robotics)
    @admin = create_person("admin", @robotics, admin: true)
  end

  # Settings write to the shared settings file; keep these out of it.
  setup do
    @original_store = Settings.instance.store
    @store_path = Rails.root.join("tmp", "hand-punches-#{Process.pid}-#{SecureRandom.hex(4)}.pstore").to_s
    Settings.instance.store = PStore.new(@store_path)
    Settings[:time_clock_hand_punches_managers_only] = "false"
  end

  teardown do
    Settings[:time_clock_hand_punches_managers_only] = "false"
    Settings.instance.store = @original_store
    FileUtils.rm_f(@store_path)
  end

  # --- the setting on: a member on the Time Clock pages -------------------

  test "with the setting on, a member can't create a punch by hand" do
    restrict_hand_punches
    sign_in @member.user

    [ nil, *SELF_ENTRY_PERMISSIONS.map { |permission| period(permission) } ].each do |period|
      assert_no_difference "TimeClockPunch.count", period&.permission || "no period" do
        post time_clock_punches_path, params: { time_clock_punch: punch_params(@member, period) }
      end
      assert_refused
    end
  end

  test "with the setting on, a member can't open the new punch form" do
    restrict_hand_punches
    sign_in @member.user

    get new_time_clock_punch_path

    assert_refused
  end

  test "with the setting on, a member can't edit or end their own punch by hand" do
    restrict_hand_punches
    sign_in @member.user

    [ nil, *SELF_ENTRY_PERMISSIONS.map { |permission| period(permission) } ].each do |period|
      punch = open_punch(@member, period)

      get edit_time_clock_punch_path(punch)
      assert_refused

      patch time_clock_punch_path(punch), params: { time_clock_punch: { end_time: 1.minute.ago } }
      assert_refused
      assert_nil punch.reload.end_time, period&.permission || "no period"
    end
  end

  test "with the setting on, a member can't hand their own punch to a teammate" do
    punch = open_punch(@member, period("added_by_team_member"))
    restrict_hand_punches
    sign_in @member.user

    patch time_clock_punch_path(punch), params: { time_clock_punch: { person_id: @classmate.id } }

    assert_refused
    assert_equal @member.id, punch.reload.person_id
  end

  test "with the setting on, a member can't delete their own punch by hand" do
    restrict_hand_punches
    sign_in @member.user

    [ nil, *SELF_ENTRY_PERMISSIONS.map { |permission| period(permission) } ].each do |period|
      punch = open_punch(@member, period)

      assert_no_difference "TimeClockPunch.count", period&.permission || "no period" do
        delete time_clock_punch_path(punch)
      end
      assert_refused
    end
  end

  test "with the setting on, the pages show a member their punches without New, Edit or Delete" do
    self_report = period("added_by_user")
    punch = open_punch(@member, self_report)
    loose_punch = open_punch(@member)
    restrict_hand_punches
    sign_in @member.user

    get time_clock_punches_path

    assert_response :success
    assert_select "tr##{dom_id(punch)}"
    assert_select "tr##{dom_id(loose_punch)}"
    assert_no_hand_entry_links(punch, loose_punch)

    get time_clock_period_path(self_report)

    assert_response :success
    assert_select "tr##{dom_id(punch)}"
    assert_no_hand_entry_links(punch, loose_punch)
  end

  # --- the setting on: managers and admins --------------------------------

  test "with the setting on, a manager still creates, edits and deletes for the people they manage" do
    team_period = period("added_by_manager")
    restrict_hand_punches
    sign_in @manager.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@member, team_period) }
    assert_redirected_to time_clock_punches_path
    punch = TimeClockPunch.find_by!(person: @member, time_clock_period: team_period)

    get edit_time_clock_punch_path(punch)
    assert_response :success

    patch time_clock_punch_path(punch), params: { time_clock_punch: { end_time: punch.start_time + 1.hour } }
    assert_redirected_to time_clock_punches_path
    assert_in_delta 1.0, punch.reload.hours, 0.1

    delete time_clock_punch_path(punch)
    assert_not TimeClockPunch.exists?(punch.id)
  end

  test "with the setting on, a manager still can't enter a punch in an admin period" do
    admin_period = period("added_by_admin")
    restrict_hand_punches
    sign_in @manager.user

    assert_no_difference "TimeClockPunch.count" do
      post time_clock_punches_path, params: { time_clock_punch: punch_params(@member, admin_period) }
    end
  end

  test "with the setting on, the pages show a manager and an admin New, Edit and Delete" do
    punch = open_punch(@member, period("added_by_manager"))
    restrict_hand_punches

    [ @manager, @admin ].each do |person|
      sign_in person.user

      get time_clock_punches_path

      assert_response :success
      assert_select "a[href=?]", new_time_clock_punch_path
      assert_select "a[href=?]", edit_time_clock_punch_path(punch)
      assert_select "a[href=?][data-turbo-method=delete]", time_clock_punch_path(punch)

      sign_out :user
    end
  end

  test "with the setting on, an admin still enters a punch in an admin period" do
    admin_period = period("added_by_admin")
    restrict_hand_punches
    sign_in @admin.user

    post time_clock_punches_path, params: { time_clock_punch: punch_params(@member, admin_period) }

    assert TimeClockPunch.exists?(person: @member, time_clock_period: admin_period)
  end

  # --- the setting on: the kiosk ------------------------------------------

  test "with the setting on, a member still clocks in and out by badge in every kind of period" do
    Token.create!(value: "8675309", tokenable: @member)
    restrict_hand_punches
    sign_in kiosk_user

    ALL_PERMISSIONS.each do |permission|
      season = period(permission)

      scan "8675309"
      post time_kiosk_path, params: { time_kiosk: kiosk_button("punch_in", time_clock_period_id: season.id) }

      punch = @member.time_clock_punches.find_by!(time_clock_period: season)
      assert_nil punch.end_time, permission

      scan "8675309"
      post time_kiosk_path, params: { time_kiosk: kiosk_button("punch_out", time_clock_punch_id: punch.id) }

      assert_not_nil punch.reload.end_time, permission
    end
  end

  test "with the setting on, a scanned manager still clocks out everyone in their period" do
    season = period("added_by_manager")
    punch = open_punch(@member, season)
    Token.create!(value: "4242", tokenable: @manager)
    restrict_hand_punches
    sign_in kiosk_user

    scan "4242"
    post time_kiosk_path, params: { time_kiosk: kiosk_button("punch_out_period", time_clock_period_id: season.id) }

    assert_not_nil punch.reload.end_time
  end

  # --- the setting off: today's behaviour ---------------------------------

  test "with the setting off, a member enters, edits and deletes their own punches by hand" do
    sign_in @member.user

    [ nil, *SELF_ENTRY_PERMISSIONS.map { |permission| period(permission) } ].each do |period|
      label = period&.permission || "no period"

      post time_clock_punches_path, params: { time_clock_punch: punch_params(@member, period) }
      assert_redirected_to time_clock_punches_path, label
      punch = TimeClockPunch.find_by!(person: @member, time_clock_period: period)

      get edit_time_clock_punch_path(punch)
      assert_response :success, label

      patch time_clock_punch_path(punch), params: { time_clock_punch: { end_time: punch.start_time + 1.hour } }
      assert_redirected_to time_clock_punches_path, label
      assert_in_delta 1.0, punch.reload.hours, 0.1, label

      delete time_clock_punch_path(punch)
      assert_not TimeClockPunch.exists?(punch.id), label
    end
  end

  test "with the setting off, the pages show a member New, Edit and Delete" do
    punch = open_punch(@member, period("added_by_user"))
    sign_in @member.user

    get time_clock_punches_path

    assert_response :success
    assert_select "a[href=?]", new_time_clock_punch_path
    assert_select "a[href=?]", edit_time_clock_punch_path(punch)
    assert_select "a[href=?][data-turbo-method=delete]", time_clock_punch_path(punch)
  end

  private

  def restrict_hand_punches
    Settings[:time_clock_hand_punches_managers_only] = "true"
  end

  def assert_refused
    assert_redirected_to root_path
    assert_equal "You are not allowed to do that", flash[:notice]
  end

  def assert_no_hand_entry_links(*punches)
    assert_select "a[href=?]", new_time_clock_punch_path, count: 0
    punches.each do |punch|
      assert_select "a[href=?]", edit_time_clock_punch_path(punch), count: 0
      assert_select "a[href=?]", time_clock_punch_path(punch), count: 0
    end
  end

  def dom_id(record)
    ActionView::RecordIdentifier.dom_id(record)
  end

  def period(permission)
    TimeClockPeriod.create!(name: permission.humanize, team: @robotics, permission: permission, start_time: 10.days.ago, end_time: 10.days.from_now)
  end

  def open_punch(person, period = nil)
    TimeClockPunch.create!(person: person, time_clock_period: period, start_time: 1.hour.ago, created_by: "kiosk")
  end

  def punch_params(person, period = nil)
    { person_id: person.id, time_clock_period_id: period&.id, start_time: 2.days.ago, end_time: 2.days.ago + 3.hours }
  end

  def kiosk_user
    user = User.create!(email: "kiosk@example.com", password: "Password1!", kiosk: true)
    Person.create!(user: user, first_name: "Kiosk", last_name: "Test")
    user
  end

  def scan(value)
    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: value } }
    assert_response :success
  end

  # The time_kiosk params of the POST button for this tool and these values.
  def kiosk_button(tool, **values)
    buttons = css_select("a[data-turbo-method=post]").map do |a|
      Rack::Utils.parse_nested_query(URI(a["href"]).query)["time_kiosk"]
    end
    buttons.find { |b| b["tool"] == tool && values.all? { |key, value| b[key.to_s] == value.to_s } } ||
      flunk("no #{tool} button for #{values} on the page")
  end

  def create_person(name, team, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager)
    person
  end
end
