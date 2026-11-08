require "test_helper"
require "phone_notifications_test_support"

class Gateway::WebPushGatewayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include PhoneNotificationsTestSupport

  test "registers as the push sending gateway" do
    gateway = create_push_gateway

    assert_equal gateway, Gateway[:push_sending]
  end

  test "asks only for a contact address" do
    assert_equal [ :contact ], Gateway::WebPushGateway.new.fields
    assert_not Gateway::WebPushGateway.new(name: "Phones").valid?
  end

  test "setup generates keys and a retried setup keeps them" do
    gateway = Gateway::WebPushGateway.create!(name: "Phones", contact: "admin@example.com")
    assert_not gateway.ready?

    gateway.finish_setup
    public_key = gateway.public_key
    assert gateway.ready?

    gateway.finish_setup
    assert_equal public_key, gateway.reload.public_key
  end

  test "replacing keys removes every subscription, which can no longer receive anything" do
    gateway = create_push_gateway
    public_key = gateway.public_key
    create_subscription(users(:one))

    gateway.replace_keys

    assert_not_equal public_key, gateway.reload.public_key
    assert_equal 0, PushSubscription.count
  end

  test "keeps an https contact as it is" do
    gateway = create_push_gateway
    gateway.update!(contact: "https://example.com/contact")

    assert_equal "https://example.com/contact", gateway.send(:vapid_subject)
  end
end
