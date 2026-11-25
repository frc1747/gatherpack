module EmailLog
  # Prepended onto Gateway::ResendSendingGateway: maps Resend's webhook
  # events onto the log and subscribes the gateway's webhook to them.
  module ResendGateway
    EVENTS = {
      "email.delivered" => :delivered,
      "email.bounced" => :bounced,
      "email.complained" => :complained,
      "email.clicked" => :clicked,
      "email.opened" => :opened
    }.freeze

    # Resend returns { id: "..." } for a sent message.
    def provider_message_id(result)
      result.respond_to?(:[]) ? (result[:id] || result["id"])&.to_s : nil
    end

    # The gateway's own handler verifies the signature first, so an unsigned
    # or forged request raises before anything is logged.
    def handle_webhook(body, headers)
      result = super
      return result unless EmailLog.enabled?

      payload = JSON.parse(body)
      kind = EVENTS[payload["type"]]
      data = payload["data"] || {}
      return result unless kind

      record_delivery_event(data["email_id"], kind,
        at: EmailLog::WebhookTime.parse(data.dig("click", "timestamp") || payload["created_at"]),
        url: data.dig("click", "link"),
        detail: data.dig("bounce", "message"))
      result
    end

    def finish_setup
      return super unless EmailLog.enabled?

      update_webhook_events!
    rescue Resend::Error => e
      Rails.logger.warn("Gateway::ResendSendingGateway##{id} could not set up its Resend webhook (#{e.class}: #{e.message}).")
    end

    def updates_webhook_events?
      true
    end

    # Subscribes this gateway's webhook to every event the log reads: updates
    # the webhook at this gateway's URL, or creates one and keeps its new
    # signing secret.
    def update_webhook_events!
      Resend.api_key = api_token
      endpoint = Rails.application.routes.url_helpers.webhook_gateway_url(self)
      events = EVENTS.keys

      listed = Resend::Webhooks.list(limit: 100)
      existing = Array(listed[:data] || listed["data"]).find { |webhook| (webhook[:endpoint] || webhook["endpoint"]) == endpoint }

      if existing
        Resend::Webhooks.update(webhook_id: existing[:id] || existing["id"], endpoint: endpoint, events: events)
      else
        webhook = Resend::Webhooks.create(endpoint: endpoint, events: events)
        update!(secret: webhook[:signing_secret])
      end
    end
  end
end
