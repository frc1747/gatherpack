require "test_helper"

class TimeKioskPolicyTest < ActiveSupport::TestCase
  test "kiosk accounts and admins may run the time kiosk" do
    assert TimeKioskPolicy.new(User.new(kiosk: true), :time_kiosk).use?
    assert TimeKioskPolicy.new(User.new(admin: true), :time_kiosk).use?
  end

  test "other accounts may not run the time kiosk" do
    assert_not TimeKioskPolicy.new(User.new, :time_kiosk).use?
    assert_not TimeKioskPolicy.new(User.new(architect: true), :time_kiosk).use?
    assert_not TimeKioskPolicy.new(nil, :time_kiosk).use?
  end
end
