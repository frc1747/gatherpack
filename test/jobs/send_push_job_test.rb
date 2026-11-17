require "test_helper"
require "phone_notifications_test_support"

class SendPushJobTest < ActiveJob::TestCase
  include PhoneNotificationsTestSupport

  FakeResponse = Struct.new(:code, :body, :message)

  setup do
    use_throwaway_settings
    set_push_flag(true)
    @gateway = create_push_gateway
    @subscription = create_subscription(users(:one))
  end

  teardown { restore_settings }

  def failing_with(error_class, code)
    error = error_class.new(FakeResponse.new(code, "", ""), "fcm.googleapis.com")
    replacing(WebPush, :payload_send, ->(**) { raise error }) { yield }
  end

  def perform
    SendPushJob.perform_now(@gateway, @subscription, "Practice moved", "/announcements")
  end

  test "the payload holds only the title and path" do
    sent = nil
    replacing(WebPush, :payload_send, ->(**args) { sent = args }) { perform }

    assert_equal({ "title" => "Practice moved", "path" => "/announcements" }, JSON.parse(sent[:message]))
    assert_equal ENDPOINT, sent[:endpoint]
    assert_equal "mailto:admin@example.com", sent[:vapid][:subject]
    assert_not_nil @subscription.reload.last_sent_at
  end

  test "the gem can sign and encrypt with the gateway's keys" do
    browser_key = OpenSSL::PKey::EC.generate("prime256v1")
    @subscription.update!(p256dh: Base64.urlsafe_encode64(browser_key.public_key.to_octet_string(:uncompressed)),
      auth: Base64.urlsafe_encode64(SecureRandom.random_bytes(16)))
    request = nil
    capture = lambda do |message:, endpoint:, p256dh:, auth:, vapid:, **options|
      request = WebPush::Request.new(message: message, subscription: { endpoint: endpoint, keys: { p256dh: p256dh, auth: auth } }, vapid: vapid, **options)
    end
    replacing(WebPush, :payload_send, capture) { perform }

    assert_match(/\Avapid t=.+,k=.+/, request.headers["Authorization"])
    assert_equal "aes128gcm", request.headers["Content-Encoding"]
    assert request.body.present?
  end

  [ [ WebPush::ExpiredSubscription, "410" ], [ WebPush::InvalidSubscription, "404" ] ].each do |error_class, code|
    test "a #{code} deletes the subscription" do
      failing_with(error_class, code) { perform }

      assert_not PushSubscription.exists?(@subscription.id)
    end
  end

  test "a 5xx retries a limited number of times and then gives up" do
    failing_with(WebPush::PushServiceError, "503") do
      perform_enqueued_jobs { SendPushJob.perform_later(@gateway, @subscription, "Practice moved", "/announcements") }
    end

    assert PushSubscription.exists?(@subscription.id)
    assert_nil @subscription.reload.last_sent_at
  end

  test "stops retrying after four attempts" do
    attempts = 0
    replacing(WebPush, :payload_send, ->(**) { attempts += 1; raise Net::ReadTimeout }) do
      perform_enqueued_jobs { SendPushJob.perform_later(@gateway, @subscription, "Practice moved", "/announcements") }
    end

    assert_equal 4, attempts
  end

  test "other refusals keep the subscription and don't retry" do
    attempts = 0
    error = WebPush::Unauthorized.new(FakeResponse.new("403", "", ""), "fcm.googleapis.com")
    replacing(WebPush, :payload_send, ->(**) { attempts += 1; raise error }) do
      perform_enqueued_jobs { SendPushJob.perform_later(@gateway, @subscription, "Practice moved", "/announcements") }
    end

    assert_equal 1, attempts
    assert PushSubscription.exists?(@subscription.id)
  end

  test "sends nothing if the flag was turned off after queueing" do
    set_push_flag(false)
    sent = false
    replacing(WebPush, :payload_send, ->(**) { sent = true }) { perform }

    assert_not sent
  end

  test "a subscription removed after queueing is ignored" do
    job = SendPushJob.new(@gateway, @subscription, "Practice moved", "/announcements")
    serialized = job.serialize
    @subscription.destroy!

    assert_nothing_raised { ActiveJob::Base.execute(serialized) }
  end
end
