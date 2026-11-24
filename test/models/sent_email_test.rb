require "test_helper"
require_relative "../support/email_log_test_helper"

class SentEmailTest < ActiveSupport::TestCase
  include EmailLogTestHelper

  setup do
    @delivered_at = Time.zone.parse("2026-11-20 20:19:00")
    @entry = SentEmail.create!(gateway: resend_gateway, address: "someone@example.com", subject: "Hello",
      status: "sent", sent_at: @delivered_at - 2.seconds, provider_message_id: "re_1")
    @entry.record_event(:delivered, at: @delivered_at)
  end

  test "delivered sets the status and time" do
    assert_equal "delivered", @entry.status
    assert_equal @delivered_at, @entry.delivered_at
  end

  test "a bounce keeps its detail and isn't undone by a later delivery" do
    entry = SentEmail.create!(address: "nobody@example.com", status: "sent")
    entry.record_event(:bounced, at: @delivered_at, detail: "Mailbox does not exist")
    entry.record_event(:delivered, at: @delivered_at + 1.minute)

    assert_equal "bounced", entry.status
    assert_equal "Mailbox does not exist", entry.problem_detail
  end

  test "a click 3 seconds after delivery is stored but not shown" do
    @entry.record_event(:clicked, at: @delivered_at + 3.seconds, url: "https://example.com/requests/1")

    assert_equal 1, @entry.click_count
    assert_equal @delivered_at + 3.seconds, @entry.first_clicked_at
    assert_nil @entry.link_clicked_at
  end

  test "a click 60 seconds after delivery is shown" do
    @entry.record_event(:clicked, at: @delivered_at + 60.seconds, url: "https://example.com/requests/1")

    assert_equal @delivered_at + 60.seconds, @entry.link_clicked_at
    assert_equal "https://example.com/requests/1", @entry.first_clicked_url
  end

  test "a person's click after a scanner's becomes the first click" do
    @entry.record_event(:clicked, at: @delivered_at + 1.second, url: "https://example.com/scanned")
    @entry.record_event(:clicked, at: @delivered_at + 7.minutes, url: "https://example.com/requests/1")
    @entry.record_event(:clicked, at: @delivered_at + 9.minutes, url: "https://example.com/requests/2")

    assert_equal 3, @entry.click_count
    assert_equal @delivered_at + 7.minutes, @entry.link_clicked_at
    assert_equal "https://example.com/requests/1", @entry.first_clicked_url
  end

  test "the scanner window is a setting" do
    Settings[:email_log_scanner_seconds] = "120"
    @entry.record_event(:clicked, at: @delivered_at + 60.seconds)

    assert_nil @entry.link_clicked_at
  end

  test "status labels can be renamed" do
    Settings[:email_log_status_delivered_label] = "Arrived"

    assert_equal "Arrived", @entry.status_label
    assert_includes EmailLog.status_options, [ "Arrived", "delivered" ]
  end

  test "an unknown event kind changes nothing" do
    assert_not @entry.record_event(:forwarded, at: Time.current)
    assert_equal "delivered", @entry.reload.status
  end
end
