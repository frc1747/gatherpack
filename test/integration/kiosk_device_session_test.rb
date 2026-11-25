require "test_helper"
require_relative "../support/settings_test_helper"

class KioskDeviceSessionTest < ActionDispatch::IntegrationTest
  include SettingsTestHelper

  setup do
    host! "localhost"
    TimeKioskController::TEST_STORE.clear
    @restore_settings = SettingsTestHelper.apply(feature_kiosk_devices: "true")
    @device = KioskDevice.create!(name: "Front door")

    @team = Team.create!(name: "Robotics", team_type: team_types(:one))
    @period = TimeClockPeriod.create!(name: "Build Season", team: @team, start_time: 1.day.ago.to_date, end_time: 1.day.from_now.to_date, permission: :added_by_user)
    @member = Person.create!(first_name: "Test", last_name: "Member")
    Membership.create!(person: @member, team: @team)
    @token = Token.create!(value: "100000001", tokenable: @member)
  end

  teardown do
    @restore_settings&.call
  end

  test "a paired browser opens the kiosk with no one signed in" do
    pair

    assert_redirected_to time_kiosk_path
    follow_redirect!
    assert_response :success
    assert_select "#kiosk-content"
    assert_not_nil @device.reload.last_seen_at
  end

  test "opening a pairing link asks before pairing" do
    code = @device.issue_pairing_code!

    get kiosk_device_pairing_path(code)

    assert_response :success
    assert_select "form[action=?] button", kiosk_device_pairing_path(code), text: "Pair"
    assert_equal @device, KioskDevice.find_by_pairing_code(code), "opening the link used up the code"
    assert cookies["kiosk_device"].blank?
  end

  test "the kiosk header shows the device's name and no brand link" do
    pair

    get time_kiosk_path

    assert_select ".kiosk-device-name", text: "Front door"
    assert_select "a.navbar-brand", count: 0
    assert_select "span.navbar-brand"
    assert_select "a[href='/']", count: 0
  end

  test "a paired browser scans a card and clocks in and out" do
    pair

    post time_kiosk_path, params: { time_kiosk: { tool: "find_token", token_value: @token.value } }
    assert_response :success
    assert_select "h3", text: @member.identifier_name

    assert_difference -> { @member.time_clock_punches.where(end_time: nil).count } do
      post time_kiosk_path, params: { time_kiosk: { tool: "punch_in", person_ref: ref_for(@member), time_clock_period_id: @period.id } }
    end
    assert_response :success

    punch = @member.time_clock_punches.find_by!(end_time: nil)
    post time_kiosk_path, params: { time_kiosk: { tool: "punch_out", person_ref: ref_for(@member), time_clock_punch_id: punch.id } }
    assert_not_nil punch.reload.end_time
  end

  test "a paired browser can't reach any other page" do
    pair

    [ root_path, people_path, person_path(@member), settings_path, kiosk_devices_path, time_clock_punches_path ].each do |path|
      get path
      assert_redirected_to new_user_session_path, path
    end
  end

  test "a revoked device is signed out on its next request" do
    pair
    get time_kiosk_path
    assert_response :success

    @device.reload.revoke!

    get time_kiosk_path
    assert_redirected_to new_user_session_path
  end

  test "pairing again ends the browser paired before" do
    pair

    @device.reload.issue_pairing_code!

    get time_kiosk_path
    assert_redirected_to new_user_session_path
  end

  test "a tampered cookie is ignored" do
    pair
    cookies["kiosk_device"] = "#{@device.id}:guessed"

    get time_kiosk_path

    assert_redirected_to new_user_session_path
  end

  test "device cookies are ignored with the feature off" do
    pair

    with_settings(feature_kiosk_devices: "false") do
      get time_kiosk_path
      assert_redirected_to new_user_session_path

      code = @device.reload.issue_pairing_code!
      get kiosk_device_pairing_path(code)
      assert_response :not_found
      post kiosk_device_pairing_path(code)
      assert_response :not_found
    end
  end

  test "an expired or used pairing code is refused" do
    code = @device.issue_pairing_code!
    travel KioskDevice::PAIRING_LIFETIME + 1.minute do
      get kiosk_device_pairing_path(code)
      assert_response :not_found
      post kiosk_device_pairing_path(code)
      assert_response :not_found
      assert cookies["kiosk_device"].blank?
    end

    code = @device.issue_pairing_code!
    post kiosk_device_pairing_path(code)
    assert_redirected_to time_kiosk_path
    cookies.delete("kiosk_device")

    post kiosk_device_pairing_path(code)
    assert_response :not_found
    assert_select ".alert", text: /expired or was already used/
    assert cookies["kiosk_device"].blank?
  end

  test "a signed-in user uses the kiosk as their own account" do
    pair
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    post user_session_path, params: { user: { email: admin.email, password: "Password1!" } }

    get time_kiosk_path

    assert_response :success
    assert_select "a.navbar-brand[href='/']"
    assert_select ".kiosk-device-name", count: 0
    get people_path
    assert_response :success
  end

  private

  def pair
    post kiosk_device_pairing_path(@device.issue_pairing_code!)
  end

  def ref_for(person)
    person.signed_id(purpose: :time_kiosk, expires_in: 5.minutes)
  end
end
