module EmailLog
  # Included into Gateway: lets a sending gateway's webhook handler update
  # the log entry for one of its messages.
  module GatewayEvents
    extend ActiveSupport::Concern

    included do
      has_many :sent_emails, dependent: nil
    end

    # Updates the entry for provider_message_id with one event
    # (SentEmail::EVENT_KINDS). Returns the entry, or nil when the log is off
    # or the message isn't one GatherPack logged.
    def record_delivery_event(provider_message_id, kind, at:, url: nil, detail: nil)
      return unless EmailLog.enabled? && provider_message_id.present?

      entry = sent_emails.find_by(provider_message_id: provider_message_id.to_s)
      return unless entry

      entry.record_event(kind, at: at, url: url, detail: detail)
      entry
    end

    # Whether this gateway can subscribe its webhook to the log's events from
    # here (Update webhook events on the gateway page).
    def updates_webhook_events?
      false
    end
  end
end
