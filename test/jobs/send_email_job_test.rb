require "test_helper"

class SendEmailJobTest < ActiveJob::TestCase
  class FlakyGateway
    attr_reader :sent

    def initialize(failures, error = Gateway::RateLimited)
      @failures = failures
      @error = error
      @sent = []
    end

    def send_message(address, subject, body)
      if @failures.positive?
        @failures -= 1
        raise @error, "slow down"
      end
      @sent << address
    end
  end

  test "a rate-limited send is retried and goes out on a later attempt" do
    gateway = Gateway::ResendSendingGateway.create!(name: "Resend", api_token: "re_test", sender: "team@example.com")
    error = Resend::Error::RateLimitExceededError.new("Too many requests", 429, {})
    refusals = 1
    sent = []
    send = lambda do |params, *|
      if refusals.positive?
        refusals -= 1
        raise error
      end
      sent << params[:to]
    end

    with_replaced(Resend::Emails.singleton_class, :send, send) do
      job = SendEmailJob.new(gateway, "person@example.com", "Subject", "<p>Body</p>")

      assert_enqueued_jobs 1, only: SendEmailJob do
        job.perform_now
      end
      assert_empty sent

      perform_enqueued_jobs(only: SendEmailJob)
      assert_equal [ "person@example.com" ], sent
    end
  end

  test "other errors are not retried" do
    gateway = FlakyGateway.new(1, ArgumentError)

    assert_no_enqueued_jobs only: SendEmailJob do
      assert_raises(ArgumentError) do
        SendEmailJob.new(gateway, "person@example.com", "Subject", "<p>Body</p>").perform_now
      end
    end
  end

  test "Resend's rate-limit error becomes Gateway::RateLimited" do
    gateway = Gateway::ResendSendingGateway.new(api_token: "re_test", sender: "team@example.com")
    error = Resend::Error::RateLimitExceededError.new("Too many requests", 429, {})

    with_replaced(Resend::Emails.singleton_class, :send, ->(*) { raise error }) do
      assert_raises(Gateway::RateLimited) { gateway.send_message("person@example.com", "Subject", "Body") }
    end
  end

  test "Postmark's 429 becomes Gateway::RateLimited and its other errors pass through" do
    gateway = Gateway::PostmarkSendingGateway.new(api_token: "pm_test", sender: "team@example.com")

    with_replaced(Postmark::ApiClient, :deliver, ->(*) { raise Postmark::UnexpectedHttpResponseError.new(429, "", {}) }) do
      assert_raises(Gateway::RateLimited) { gateway.send_message("person@example.com", "Subject", "Body") }
    end
    with_replaced(Postmark::ApiClient, :deliver, ->(*) { raise Postmark::InternalServerError.new(500, "", {}) }) do
      assert_raises(Postmark::InternalServerError) { gateway.send_message("person@example.com", "Subject", "Body") }
    end
  end

  private

  # Swaps one method for the block's duration (minitest 6 has no stubs).
  def with_replaced(klass, name, body)
    original = klass.instance_method(name)
    klass.define_method(name, &body)
    yield
  ensure
    klass.define_method(name, original)
  end
end
