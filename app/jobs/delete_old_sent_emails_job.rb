# Daily: deletes sent email log entries older than email_log_keep_days, so
# addresses and subjects aren't kept longer than they're useful.
class DeleteOldSentEmailsJob < ApplicationJob
  queue_as :default

  def perform
    return unless EmailLog.enabled?

    SentEmail.delete_older_than(EmailLog.keep_days)
  end
end
