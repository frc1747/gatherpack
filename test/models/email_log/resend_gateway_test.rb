require "test_helper"
require_relative "../../support/email_log_test_helper"

class EmailLog::ResendGatewayTest < ActiveSupport::TestCase
  include EmailLogTestHelper

  SECRET = "whsec_#{Base64.strict_encode64('resend-test-signing-secret')}".freeze

  setup do
    @gateway = resend_gateway(secret: SECRET)
    @entry = SentEmail.create!(gateway: @gateway, address: "someone@example.com", subject: "Hello",
      status: "sent", sent_at: 1.hour.ago, provider_message_id: "re_abc")
  end

  test "delivered, bounced, complained, clicked and opened update the entry" do
    deliver_webhook(event("email.delivered", created_at: "2026-11-20T20:19:00.000Z"))
    assert_equal "delivered", @entry.reload.status
    assert_equal Time.utc(2026, 11, 20, 20, 19), @entry.delivered_at

    deliver_webhook(event("email.clicked", click: { "link" => "https://example.com/r/1", "timestamp" => "2026-11-20T20:26:00.000Z" }))
    assert_equal Time.utc(2026, 11, 20, 20, 26), @entry.reload.link_clicked_at
    assert_equal "https://example.com/r/1", @entry.first_clicked_url

    deliver_webhook(event("email.opened", created_at: "2026-11-20T20:25:00.000Z"))
    assert_equal Time.utc(2026, 11, 20, 20, 25), @entry.reload.opened_at

    deliver_webhook(event("email.complained"))
    assert_equal "complained", @entry.reload.status

    deliver_webhook(event("email.bounced", bounce: { "message" => "Mailbox full" }))
    assert_equal "bounced", @entry.reload.status
    assert_equal "Mailbox full", @entry.problem_detail
  end

  test "only the entry with that message id changes" do
    other = SentEmail.create!(gateway: @gateway, address: "other@example.com", status: "sent", provider_message_id: "re_other")

    deliver_webhook(event("email.delivered"))

    assert_equal "delivered", @entry.reload.status
    assert_equal "sent", other.reload.status
  end

  test "an unknown message id is ignored" do
    assert_nothing_raised { deliver_webhook(event("email.delivered", email_id: "re_unknown")) }
    assert_equal "sent", @entry.reload.status
  end

  test "an unsigned request is refused" do
    body = event("email.delivered").to_json

    assert_raises(RuntimeError) do
      @gateway.handle_webhook(body, { "HTTP_SVIX_ID" => "msg_1", "HTTP_SVIX_TIMESTAMP" => Time.now.to_i.to_s, "HTTP_SVIX_SIGNATURE" => "v1,forged" })
    end
    assert_equal "sent", @entry.reload.status
  end

  test "webhooks change nothing when the feature is off" do
    turn_off_email_log

    deliver_webhook(event("email.delivered"))

    assert_equal "sent", @entry.reload.status
  end

  test "the provider id comes from Resend's response" do
    assert_equal "re_1", @gateway.provider_message_id({ id: "re_1" })
    assert_nil @gateway.provider_message_id(nil)
  end

  test "update webhook events updates the webhook at this gateway's URL" do
    url = Rails.application.routes.url_helpers.webhook_gateway_url(@gateway)
    updated = nil

    stubbing(Resend::Webhooks, :list, ->(_params = {}) { { data: [ { "id" => "wh_1", "endpoint" => url } ] } }) do
      stubbing(Resend::Webhooks, :update, ->(params = {}) { updated = params }) do
        @gateway.update_webhook_events!
      end
    end

    assert_equal "wh_1", updated[:webhook_id]
    assert_equal EmailLog::ResendGateway::EVENTS.keys, updated[:events]
    assert_equal SECRET, @gateway.reload.secret
  end

  test "update webhook events creates a webhook and keeps its secret when there's none" do
    created = nil

    stubbing(Resend::Webhooks, :list, ->(_params = {}) { { data: [] } }) do
      stubbing(Resend::Webhooks, :create, ->(params = {}) { created = params; { id: "wh_2", signing_secret: "whsec_new" } }) do
        @gateway.update_webhook_events!
      end
    end

    assert_equal EmailLog::ResendGateway::EVENTS.keys, created[:events]
    assert_equal "whsec_new", @gateway.reload.secret
  end

  test "the gateway page offers Update webhook events only when the feature is on" do
    assert_includes @gateway.routes.map { |route| route[:name] }, "Update webhook events"

    turn_off_email_log
    assert_empty @gateway.routes
  end

  private
    def event(type, email_id: "re_abc", created_at: "2026-11-20T20:30:00.000Z", **data)
      { "type" => type, "created_at" => created_at, "data" => { "email_id" => email_id, "to" => [ "someone@example.com" ] }.merge(data.stringify_keys) }
    end

    def deliver_webhook(payload)
      body = payload.to_json
      msg_id = "msg_#{SecureRandom.hex(4)}"
      timestamp = Time.now.to_i
      signature = Svix::Webhook.new(SECRET).sign(msg_id, timestamp, body)

      @gateway.handle_webhook(body, { "HTTP_SVIX_ID" => msg_id, "HTTP_SVIX_TIMESTAMP" => timestamp.to_s, "HTTP_SVIX_SIGNATURE" => signature })
    end
end
