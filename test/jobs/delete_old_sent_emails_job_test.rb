require "test_helper"
require_relative "../support/email_log_test_helper"

class DeleteOldSentEmailsJobTest < ActiveJob::TestCase
  include EmailLogTestHelper

  setup do
    @old = SentEmail.create!(address: "old@example.com", status: "delivered", created_at: 200.days.ago)
    @recent = SentEmail.create!(address: "recent@example.com", status: "delivered", created_at: 20.days.ago)
  end

  test "deletes only entries older than the setting" do
    DeleteOldSentEmailsJob.perform_now

    assert_not SentEmail.exists?(@old.id)
    assert SentEmail.exists?(@recent.id)
  end

  test "follows a shorter setting" do
    Settings[:email_log_keep_days] = "10"

    DeleteOldSentEmailsJob.perform_now

    assert_not SentEmail.exists?(@recent.id)
  end

  test "does nothing when the feature is off" do
    turn_off_email_log

    assert_no_difference -> { SentEmail.count } do
      DeleteOldSentEmailsJob.perform_now
    end
  end

  test "is scheduled daily through config/recurring.d" do
    task = GatherPack::RecurringSchedule.tasks[:delete_old_sent_emails]

    assert_equal "DeleteOldSentEmailsJob", task[:class]
    assert_match(/every day/, task[:schedule])
  end
end
