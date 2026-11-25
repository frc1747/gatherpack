module EmailLog
  # Prepended onto Gateway::PostmarkSendingGateway: maps Postmark's webhook
  # record types onto the log and subscribes the gateway's webhook to them.
  module PostmarkGateway
    RECORD_TYPES = {
      "Delivery" => :delivered,
      "Bounce" => :bounced,
      "SpamComplaint" => :complained,
      "Click" => :clicked,
      "Open" => :opened
    }.freeze

    TRIGGERS = {
      Delivery: { Enabled: true },
      Bounce: { Enabled: true, IncludeContent: false },
      SpamComplaint: { Enabled: true, IncludeContent: false },
      Click: { Enabled: true },
      Open: { Enabled: true, PostFirstOpenOnly: true },
      SubscriptionChange: { Enabled: true }
    }.freeze

    # Postmark returns { message_id: "..." } for a sent message.
    def provider_message_id(result)
      result.respond_to?(:[]) ? (result[:message_id] || result["MessageID"])&.to_s : nil
    end

    def handle_webhook(body, headers)
      result = super
      return result unless EmailLog.enabled?

      payload = JSON.parse(body)
      kind = RECORD_TYPES[payload["RecordType"]]
      return result unless kind

      at = payload["DeliveredAt"] || payload["BouncedAt"] || payload["ReceivedAt"]
      record_delivery_event(payload["MessageID"], kind,
        at: EmailLog::WebhookTime.parse(at),
        url: payload["OriginalLink"],
        detail: payload["Description"])
      result
    end

    def finish_setup
      return super unless EmailLog.enabled?

      update_webhook_events!
    end

    def updates_webhook_events?
      true
    end

    # Subscribes this gateway's webhook to every record type the log reads:
    # updates the webhook at this gateway's URL, or creates one.
    def update_webhook_events!
      client = Postmark::ApiClient.new(api_token)
      url = Rails.application.routes.url_helpers.webhook_gateway_url(self)
      existing = Array(client.get_webhooks(message_stream: "outbound")).find { |webhook| webhook[:url] == url }

      if existing
        client.update_webhook(existing[:id], url: url, triggers: TRIGGERS)
      else
        client.create_webhook(url: url, message_stream: "outbound", triggers: TRIGGERS)
      end
    end
  end
end
