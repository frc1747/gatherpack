require "test_helper"

class KioskDevicePolicyTest < ActiveSupport::TestCase
  setup do
    @device = KioskDevice.create!(name: "Front door")
  end

  test "admins may list, add, rename, revoke and pair devices" do
    admin = User.new(admin: true)
    policy = KioskDevicePolicy.new(admin, @device)

    assert KioskDevicePolicy.new(admin, KioskDevice).index?
    assert KioskDevicePolicy.new(admin, KioskDevice.new).create?
    assert policy.update?
    assert policy.revoke?
    assert policy.pair?
    assert_includes KioskDevicePolicy::Scope.new(admin, KioskDevice).resolve, @device
  end

  test "no one else may" do
    [ User.new, User.new(kiosk: true), User.new(architect: true), nil ].each do |user|
      policy = KioskDevicePolicy.new(user, @device)

      assert_not KioskDevicePolicy.new(user, KioskDevice).index?
      assert_not KioskDevicePolicy.new(user, KioskDevice.new).create?
      assert_not policy.update?
      assert_not policy.revoke?
      assert_not policy.pair?
      assert_empty KioskDevicePolicy::Scope.new(user, KioskDevice).resolve
    end
  end

  test "a paired device may run the time kiosk" do
    assert TimeKioskPolicy.new(@device, :time_kiosk).use?
  end
end
