# Sent email log: every email GatherPack sends, updated from the sending
# service's webhooks (delivered, bounced, complained, link clicked, opened).
# Off by default (feature_email_log). Patches SendEmailJob and the Resend and
# Postmark gateways from here, so their files don't change.

# Routes are in config/routes/email_log.rb; the controllers check the
# feature switch. The daily clean-up is in config/recurring.d/email_log.yml.
Rails.application.config.to_prepare do
  GatherPack::Features.register_section("Email", position: 45)

  GatherPack::Features.register(
    GatherPack::Feature.new(
      key: :email_log,
      label: "Sent email log",
      description: "Keep a log of every email sent, with delivery, bounces and link clicks reported by the sending service",
      default_enabled: false,
      setup_section: "Email",
      setup_items: [
        GatherPack::Feature::SetupItem.new(label: "Sent email", path: :sent_emails_path,
          policy_check: ->(view) { SentEmailPolicy.new(view.current_user, SentEmail).index? })
      ]
    )
  )

  EmailLog.register_settings

  Gateway.include(EmailLog::GatewayEvents)
  SendEmailJob.prepend(EmailLog::SendEmailJobLogging)
  Gateway::ResendSendingGateway.prepend(EmailLog::ResendGateway, EmailLog::WebhookEventsButton)
  Gateway::PostmarkSendingGateway.prepend(EmailLog::PostmarkGateway, EmailLog::WebhookEventsButton)
end
