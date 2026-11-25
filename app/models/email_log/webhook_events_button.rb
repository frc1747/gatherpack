module EmailLog
  # Prepended onto the sending gateways that can update their webhook: adds
  # Update webhook events to the gateway page's buttons (Gateway#routes).
  module WebhookEventsButton
    def routes
      return super unless EmailLog.enabled?

      super + [ { name: "Update webhook events", path: Rails.application.routes.url_helpers.gateway_webhook_events_path(self) } ]
    end
  end
end
