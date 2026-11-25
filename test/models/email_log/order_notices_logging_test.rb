require "test_helper"
require "support/orders_world"
require "support/email_log_test_helper"

# Order notices name the person and the request in the sent email log.
class EmailLog::OrderNoticesLoggingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OrdersWorld
  include EmailLogTestHelper

  setup do
    @world = build_orders_world
    @gateway = resend_gateway
    @gateway.define_singleton_method(:send_message) { |_address, _subject, _body| { id: "re_#{SecureRandom.hex(4)}" } }
  end

  # Runs each queued email through the job with the stubbed gateway.
  def send_queued_emails
    jobs = enqueued_jobs.select { |job| job[:job] == SendEmailJob }
    clear_enqueued_jobs
    jobs.each do |job|
      _gateway, address, subject, body, options = ActiveJob::Arguments.deserialize(job[:args])
      SendEmailJob.perform_now(@gateway, address, subject, body, **options.to_h.symbolize_keys)
    end
  end

  test "a submitted request's notices are logged about the request, for each approver" do
    with_orders(@world, orders_notices: "each", feature_email_log: "true") do
      draft = draft_request(@world)
      clear_enqueued_jobs
      draft.submit!(by: @world.requester)
      send_queued_emails

      entries = SentEmail.where(about: draft)
      assert_equal [ @world.admin, @world.manager, @world.mentor ].map(&:id).sort, entries.map(&:person_id).sort
      assert entries.all? { |entry| entry.subject.include?("To approve") }
    end
  end

  test "reminders are logged about their request too" do
    with_orders(@world, orders_notices: "each", feature_email_log: "true") do
      request = submitted_request(@world)
      clear_enqueued_jobs
      OrderNotices.new.undecided(request)
      send_queued_emails

      assert_equal 3, SentEmail.where(about: request).count
    end
  end

  test "a notice about one item is logged about its request" do
    with_orders(@world, orders_notices: "each", feature_email_log: "true") do
      request = submitted_request(@world)
      clear_enqueued_jobs
      OrderNotices.new.backordered(request.order_lines.first)
      send_queued_emails

      assert_equal [ @world.requester.id ], SentEmail.where(about: request).pluck(:person_id)
    end
  end

  test "with the email log off the notices still go and nothing is logged" do
    turn_off_email_log
    with_orders(@world, orders_notices: "each") do
      draft = draft_request(@world)
      clear_enqueued_jobs
      draft.submit!(by: @world.requester)

      assert_equal 3, enqueued_jobs.count { |job| job[:job] == SendEmailJob }
      assert_no_difference -> { SentEmail.count } do
        send_queued_emails
      end
    end
  end
end
