require "test_helper"
require_relative "../support/email_log_test_helper"

class SendEmailJobLoggingTest < ActiveJob::TestCase
  include EmailLogTestHelper

  setup do
    @gateway = resend_gateway
    @gateway.define_singleton_method(:send_message) { |_address, _subject, _body| { id: "re_msg_1" } }
  end

  test "logs the email and stores the id the gateway returns" do
    assert_difference -> { SentEmail.count }, 1 do
      SendEmailJob.perform_now(@gateway, "someone@example.com", "Practice moved", "<p>Body</p>")
    end

    entry = SentEmail.last
    assert_equal @gateway, entry.gateway
    assert_equal "someone@example.com", entry.address
    assert_equal "Practice moved", entry.subject
    assert_equal "sent", entry.status
    assert_equal "re_msg_1", entry.provider_message_id
    assert_not_nil entry.sent_at
  end

  test "keeps the person and record the caller names" do
    person = people(:two)
    about = announcements(:one)

    SendEmailJob.perform_now(@gateway, "someone@example.com", "Hello", "Body", person: person, about: about)

    entry = SentEmail.last
    assert_equal person, entry.person
    assert_equal about, entry.about
  end

  test "finds the person who signs in with the address when the caller doesn't say" do
    SendEmailJob.perform_now(@gateway, users(:one).email, "Hello", "Body")

    assert_equal people(:one), SentEmail.last.person
  end

  test "keyword arguments survive being queued" do
    assert_enqueued_with(job: SendEmailJob) do
      SendEmailJob.perform_later(@gateway, "someone@example.com", "Hello", "Body", person: people(:one))
    end
  end

  test "a gateway that returns no id still logs the send" do
    @gateway.define_singleton_method(:send_message) { |_address, _subject, _body| Object.new }

    SendEmailJob.perform_now(@gateway, "someone@example.com", "Hello", "Body")

    assert_equal "sent", SentEmail.last.status
    assert_nil SentEmail.last.provider_message_id
  end

  test "marks the entry failed when the job gives up" do
    @gateway.define_singleton_method(:send_message) { |_address, _subject, _body| raise Resend::Error, "Domain not verified" }

    assert_raises(Resend::Error) do
      SendEmailJob.perform_now(@gateway, "someone@example.com", "Hello", "Body")
    end

    entry = SentEmail.last
    assert_equal "failed", entry.status
    assert_equal "Domain not verified", entry.problem_detail
    assert_not_nil entry.problem_at
  end

  test "a retried job keeps one entry" do
    attempts = 0
    @gateway.define_singleton_method(:send_message) do |_address, _subject, _body|
      attempts += 1
      raise Resend::Error, "Busy" if attempts == 1
      { id: "re_msg_2" }
    end
    job = SendEmailJob.new(@gateway, "someone@example.com", "Hello", "Body")

    assert_raises(Resend::Error) { job.perform(*job.arguments) }
    job.perform(*job.arguments)

    assert_equal 1, SentEmail.where(job_id: job.job_id).count
    assert_equal "re_msg_2", SentEmail.find_by(job_id: job.job_id).provider_message_id
  end

  test "logs nothing when the feature is off" do
    turn_off_email_log
    sent = false
    @gateway.define_singleton_method(:send_message) { |_address, _subject, _body| sent = true }

    assert_no_difference -> { SentEmail.count } do
      SendEmailJob.perform_now(@gateway, "someone@example.com", "Hello", "Body")
    end
    assert sent
  end
end
