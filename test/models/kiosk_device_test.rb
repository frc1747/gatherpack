require "test_helper"

class KioskDeviceTest < ActiveSupport::TestCase
  setup do
    @device = KioskDevice.create!(name: "Front door")
  end

  test "stores only digests of the pairing code and the secret" do
    code = @device.issue_pairing_code!
    assert_equal Digest::SHA256.hexdigest(code), @device.pairing_code_digest
    assert_not_includes @device.attributes.values.compact.map(&:to_s), code

    secret = @device.pair!(code)
    assert_equal Digest::SHA256.hexdigest(secret), @device.reload.secret_digest
    assert_not_includes @device.attributes.values.compact.map(&:to_s), secret
  end

  test "a pairing code finds its device until it expires" do
    code = @device.issue_pairing_code!

    assert_equal @device, KioskDevice.find_by_pairing_code(code)
    assert_nil KioskDevice.find_by_pairing_code("not-the-code")
    assert_nil KioskDevice.find_by_pairing_code(nil)
    travel KioskDevice::PAIRING_LIFETIME + 1.minute do
      assert_nil KioskDevice.find_by_pairing_code(code)
      assert_nil @device.reload.pair!(code)
    end
  end

  test "a pairing code works once" do
    code = @device.issue_pairing_code!

    assert @device.pair!(code)
    assert_nil @device.pair!(code)
    assert_nil KioskDevice.find_by_pairing_code(code)
    assert_nil @device.reload.pairing_expires_at
  end

  test "pairing refuses another device's code" do
    other = KioskDevice.create!(name: "Shop")
    other_code = other.issue_pairing_code!
    @device.issue_pairing_code!

    assert_nil @device.pair!(other_code)
  end

  test "authenticates the cookie's id and secret" do
    secret = @device.pair!(@device.issue_pairing_code!)

    assert_equal @device, KioskDevice.authenticate("#{@device.id}:#{secret}")
    assert_nil KioskDevice.authenticate("#{@device.id}:wrong")
    assert_nil KioskDevice.authenticate("#{KioskDevice.create!(name: "Other").id}:#{secret}")
    assert_nil KioskDevice.authenticate("not-a-uuid:#{secret}")
    assert_nil KioskDevice.authenticate(@device.id)
    assert_nil KioskDevice.authenticate(nil)
  end

  test "a revoked device no longer authenticates or pairs" do
    secret = @device.pair!(@device.issue_pairing_code!)

    @device.revoke!

    assert @device.revoked?
    assert_nil KioskDevice.authenticate("#{@device.id}:#{secret}")
  end

  test "pairing again invalidates the old secret" do
    old_secret = @device.pair!(@device.issue_pairing_code!)

    code = @device.issue_pairing_code!
    assert_nil KioskDevice.authenticate("#{@device.id}:#{old_secret}")

    new_secret = @device.pair!(code)
    assert_equal @device, KioskDevice.authenticate("#{@device.id}:#{new_secret}")
    assert_nil KioskDevice.authenticate("#{@device.id}:#{old_secret}")
  end

  test "pairing a revoked device again brings it back" do
    @device.revoke!

    secret = @device.pair!(@device.issue_pairing_code!)

    assert_not @device.revoked?
    assert_equal @device, KioskDevice.authenticate("#{@device.id}:#{secret}")
  end

  test "last seen is written at most once an interval" do
    @device.seen!
    first = @device.reload.last_seen_at
    assert first

    travel 10.minutes do
      @device.seen!
      assert_equal first, @device.reload.last_seen_at
    end
    travel KioskDevice::SEEN_INTERVAL + 1.minute do
      @device.seen!
      assert_operator @device.reload.last_seen_at, :>, first
    end
  end

  test "needs a name" do
    assert_not KioskDevice.new(name: "").valid?
  end
end
