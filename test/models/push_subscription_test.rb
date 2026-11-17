require "test_helper"
require "phone_notifications_test_support"

class PushSubscriptionTest < ActiveSupport::TestCase
  include PhoneNotificationsTestSupport

  def subscription(endpoint)
    PushSubscription.new(user: users(:one), endpoint: endpoint, p256dh: "BPublicKey", auth: "authSecret")
  end

  test "accepts the browser vendors' push services" do
    [ ENDPOINT, "https://updates.push.services.mozilla.com/wpush/v2/x", "https://web.push.apple.com/x", "https://wns2-par02p.notify.windows.com/w/?token=x" ].each do |endpoint|
      assert subscription(endpoint).valid?, endpoint
    end
  end

  test "refuses any other address, so the server can't be sent elsewhere" do
    [ "http://fcm.googleapis.com/x", "https://localhost/x", "https://169.254.169.254/latest", "https://fcm.googleapis.com.evil.test/x",
      "https://fcm.googleapis.com:8443/x", "https://me@fcm.googleapis.com/x", "not a url", "" ].each do |endpoint|
      assert_not subscription(endpoint).valid?, endpoint
    end
  end

  test "keys are stored encrypted when encryption is configured" do
    record = create_subscription(users(:one))
    stored = PushSubscription.connection.select_value("SELECT auth FROM push_subscriptions WHERE id = #{PushSubscription.connection.quote(record.id)}")

    if ActiveRecord::Encryption.config.has_primary_key?
      assert_not_equal "authSecret", stored
    else
      assert_equal "authSecret", stored
    end
    assert_equal "authSecret", record.reload.auth
  end

  test "removing a login removes its devices and preferences" do
    user = users(:one)
    create_subscription(user)
    enable_topics(user, :announcements)
    user.person&.update_column(:user_id, nil)

    user.reload.destroy!

    assert_equal 0, PushSubscription.where(user_id: user.id).count
    assert_equal 0, PushPreference.where(user_id: user.id).count
  end

  test "isn't audited or hooked" do
    assert_not PushSubscription.include?(CanBeHooked)
    assert_not PushPreference.include?(CanBeHooked)
    assert_not PushSubscription.respond_to?(:paper_trail_options)
  end

  test "labels a device from its user agent" do
    assert_equal "Chrome on Android", PushSubscription.device_label("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36")
    assert_equal "Safari on iPhone", PushSubscription.device_label("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148")
    assert_equal "Browser", PushSubscription.device_label(nil)
  end
end
