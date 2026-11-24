require "test_helper"
require_relative "../support/settings_test_helper"

class KioskDevicesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SettingsTestHelper

  setup do
    host! "localhost"
    @restore_settings = SettingsTestHelper.apply(feature_kiosk_devices: "true")
    @admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    @member = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
    Person.create!(user: @member, first_name: "Max", last_name: "Member")
    @device = KioskDevice.create!(name: "Front door")
  end

  teardown do
    @restore_settings&.call
  end

  test "lists devices with when each was last seen" do
    @device.update!(last_seen_at: 2.hours.ago)
    KioskDevice.create!(name: "Shop")
    sign_in @admin

    get kiosk_devices_path

    assert_response :success
    assert_select "td", text: "Front door"
    assert_select "td", text: "Shop"
    assert_select "td", text: "about 2 hours ago"
    assert_select "td", text: "Never"
  end

  test "adding a device shows its pairing link once" do
    sign_in @admin

    assert_difference -> { KioskDevice.count } do
      post kiosk_devices_path, params: { kiosk_device: { name: "Gym" } }
    end

    device = KioskDevice.find_by!(name: "Gym")
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal @admin, device.created_by
    link = css_select("#pairing-link").text
    code = link.delete_prefix("http://localhost/time_kiosk/pair/")
    assert_not_equal link, code
    assert_equal device, KioskDevice.find_by_pairing_code(code)

    get kiosk_devices_path
    assert_not_includes response.body, code
  end

  test "a device needs a name" do
    sign_in @admin

    assert_no_difference -> { KioskDevice.count } do
      post kiosk_devices_path, params: { kiosk_device: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "renames a device" do
    sign_in @admin

    patch kiosk_device_path(@device), params: { kiosk_device: { name: "Back door" } }

    assert_redirected_to kiosk_devices_path
    assert_equal "Back door", @device.reload.name
  end

  test "revokes a device" do
    @device.pair!(@device.issue_pairing_code!)
    sign_in @admin

    patch revoke_kiosk_device_path(@device)

    assert_redirected_to kiosk_devices_path
    assert @device.reload.revoked?
    assert_not @device.paired?
  end

  test "pairing again issues a new code and ends the old pairing" do
    @device.pair!(@device.issue_pairing_code!)
    sign_in @admin

    post pair_kiosk_device_path(@device)

    assert_response :success
    code = css_select("#pairing-link").text.delete_prefix("http://localhost/time_kiosk/pair/")
    assert_equal @device, KioskDevice.find_by_pairing_code(code)
    assert_not @device.reload.paired?
  end

  test "only admins manage devices" do
    sign_in @member

    get kiosk_devices_path
    assert_redirected_to root_path
    post kiosk_devices_path, params: { kiosk_device: { name: "Gym" } }
    assert_redirected_to root_path
    patch revoke_kiosk_device_path(@device)
    post pair_kiosk_device_path(@device)
    patch kiosk_device_path(@device), params: { kiosk_device: { name: "Back door" } }

    assert_equal "Front door", @device.reload.name
    assert_not @device.revoked?
    assert_nil @device.pairing_code_digest
    assert_not KioskDevice.exists?(name: "Gym")
  end

  test "is off with the feature" do
    sign_in @admin

    with_settings(feature_kiosk_devices: "false") do
      get kiosk_devices_path
      assert_redirected_to root_path

      post pair_kiosk_device_path(@device)
      assert_redirected_to root_path
      assert_nil @device.reload.pairing_code_digest
    end
  end

  test "is listed in setup for admins only" do
    sign_in @admin
    get setup_path
    assert_select "a[href=?]", kiosk_devices_path

    sign_out @admin
    sign_in @member
    get setup_path
    assert_select "a[href=?]", kiosk_devices_path, count: 0
  end
end
