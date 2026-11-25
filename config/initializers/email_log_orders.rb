# Sent email log on order requests: order notices name the request they're
# about, and the request's page lists the approvers emailed for each step
# (orders/requests/_approval_emails). Shown only while both the email log and
# orders are on.
Rails.application.config.to_prepare do
  OrderNotices.prepend(EmailLog::OrderNoticesAbout) unless OrderNotices < EmailLog::OrderNoticesAbout
end
