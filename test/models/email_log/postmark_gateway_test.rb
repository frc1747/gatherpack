require "test_helper"
require_relative "../../support/email_log_test_helper"

class EmailLog::PostmarkGatewayTest < ActiveSupport::TestCase
  include EmailLogTestHelper

  setup do
    @gateway = postmark_gateway
    @entry = SentEmail.create!(gateway: @gateway, address: "someone@example.com", subject: "Hello",
      status: "sent", sent_at: 1.hour.ago, provider_message_id: "pm-abc")
  end

  test "Delivery, Click, Open, SpamComplaint and Bounce update the entry" do
    deliver_webhook("RecordType" => "Delivery", "DeliveredAt" => "2026-11-20T20:19:00Z")
    assert_equal "delivered", @entry.reload.status
    assert_equal Time.utc(2026, 11, 20, 20, 19), @entry.delivered_at

    deliver_webhook("RecordType" => "Click", "ReceivedAt" => "2026-11-20T20:26:00Z", "OriginalLink" => "https://example.com/r/1")
    assert_equal Time.utc(2026, 11, 20, 20, 26), @entry.reload.link_clicked_at
    assert_equal "https://example.com/r/1", @entry.first_clicked_url

    deliver_webhook("RecordType" => "Open", "ReceivedAt" => "2026-11-20T20:25:00Z")
    assert_equal Time.utc(2026, 11, 20, 20, 25), @entry.reload.opened_at

    deliver_webhook("RecordType" => "SpamComplaint", "BouncedAt" => "2026-11-20T21:00:00Z")
    assert_equal "complained", @entry.reload.status

    deliver_webhook("RecordType" => "Bounce", "BouncedAt" => "2026-11-20T21:05:00Z", "Description" => "The server was unable to deliver your message")
    assert_equal "bounced", @entry.reload.status
    assert_equal "The server was unable to deliver your message", @entry.problem_detail
    assert_equal Time.utc(2026, 11, 20, 21, 5), @entry.problem_at
  end

  test "an unknown message id is ignored" do
    assert_nothing_raised { deliver_webhook("RecordType" => "Delivery", "MessageID" => "pm-unknown") }
    assert_equal "sent", @entry.reload.status
  end

  test "webhooks change nothing when the feature is off" do
    turn_off_email_log

    deliver_webhook("RecordType" => "Delivery")

    assert_equal "sent", @entry.reload.status
  end

  test "the provider id comes from Postmark's response" do
    assert_equal "pm-1", @gateway.provider_message_id({ message_id: "pm-1" })
  end

  private
    def deliver_webhook(payload)
      @gateway.handle_webhook({ "MessageID" => "pm-abc" }.merge(payload).to_json, {})
    end
end
