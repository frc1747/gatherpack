class Gateway::ResendSendingGateway < Gateway
  Gateway.register(self, :email_sending)
  store_accessor :configuration, :api_token
  store_accessor :configuration, :sender
  store_accessor :configuration, :secret

  def fields
    [ :api_token, :sender, :secret ]
  end

  def identifier_icon
    "envelopes-bulk"
  end

  def send_later(address, subject, body)
    address = [ address ].flatten
    address.each do |a|
      SendEmailJob.perform_later(self, a, subject, body)
    end
  end

  def send_message(address, subject, body)
    Resend.api_key = api_token

    Resend::Emails.send({
      from: sender,
      to: address,
      subject: subject,
      html: body
    })
  end

  def self.webhook_headers
    [ "HTTP_SVIX_ID", "HTTP_SVIX_TIMESTAMP", "HTTP_SVIX_SIGNATURE" ]
  end

  def verify_webhook(body, headers)
    return refuse_without_secret if secret.blank?

    Svix::Webhook.new(secret).verify(body, svix_headers(headers))
    true
  rescue Svix::WebhookVerificationError
    false
  end

  def webhook_problem
    "not ready: no webhook signing secret" if secret.blank?
  end

  def handle_webhook(body, headers)
    return refuse_without_secret if secret.blank?

    begin
      Svix::Webhook.new(secret).verify(body, svix_headers(headers))
    rescue Svix::WebhookVerificationError => e
      raise "Resend webhook signature verification failed. #{e.message}"
    end

    payload = JSON.parse(body)

    case payload["type"]
    when "email.bounced"
      # disable all notifications for this gateway for this user
    when "email.complained"
      # disable all notifications for this gateway for this user
    end
  end

  def finish_setup
    Resend.api_key = api_token

    webhook = Resend::Webhooks.create(
      endpoint: Rails.application.routes.url_helpers.webhook_gateway_url(self),
      events: [ "email.bounced", "email.complained" ]
    )

    update(secret: webhook[:signing_secret])
  rescue Resend::Error => e
    Rails.logger.warn("Gateway::ResendSendingGateway##{id} could not auto-create a Resend webhook (#{e.class}: #{e.message}). This usually means the API token is restricted to sending only. Create the webhook manually in the Resend dashboard and paste its signing secret into this gateway's Secret field.")
  end

  private
    def refuse_without_secret
      Rails.logger.error("Gateway::ResendSendingGateway##{id} (#{name}) refused a Resend event: this gateway has no webhook signing secret. Copy the webhook's signing secret from the Resend dashboard into this gateway's Secret field.")
      false
    end

    def svix_headers(headers)
      {
        "svix-id" => headers["HTTP_SVIX_ID"],
        "svix-timestamp" => headers["HTTP_SVIX_TIMESTAMP"],
        "svix-signature" => headers["HTTP_SVIX_SIGNATURE"]
      }
    end
end
