class Gateway::StripeGateway < Gateway
  Gateway.register(self, :payment)
  store_accessor :configuration, :secret_key
  store_accessor :configuration, :public_key
  store_accessor :configuration, :test_mode
  store_accessor :configuration, :secret

  def fields
    [ :public_key, :secret_key, :test_mode, :secret ]
  end

  def identifier_icon
    [ "cc-stripe", "brands" ]
  end

  def start_payment(ledger_payment, creator)
    ledger_entry = LedgerEntry.create(ledger: ledger_payment.ledger, amount: ledger_payment.amount, finalized: false, created_by: creator, remark: "Paid via Stripe | #{ledger_payment.remark}")
    checkout = Stripe::Checkout::Session.create({
      line_items: [
        {
          price_data: {
            currency: "usd",
            unit_amount: ledger_entry.amount_cents,
            product_data: {
              name: ledger_payment.remark
            }
          },
          quantity: 1

        }
      ],
      mode: "payment",
      success_url: Rails.application.routes.url_helpers.ledger_url(ledger_entry.ledger)
    },
    {
      api_key: secret_key
    }
    )
    ledger_entry.update(metadata: { gateway_id: id, stripe_checkout_session: { id: checkout.id, url: checkout.url } })
    ledger_entry
  end

  def self.webhook_headers
    [ "HTTP_STRIPE_SIGNATURE" ]
  end

  def handle_webhook(payload, headers)
    if secret.blank?
      Rails.logger.error("Gateway::StripeGateway##{id} (#{name}) refused a Stripe event: this gateway has no webhook signing secret. Copy the endpoint's signing secret from the Stripe dashboard into this gateway's Secret field.")
      return
    end

    begin
      event = Stripe::Webhook.construct_event(payload, headers["HTTP_STRIPE_SIGNATURE"], secret)
    rescue Stripe::SignatureVerificationError => e
      raise "Stripe webhook signature verification failed. #{e.message}"
    end

    case event.type
    when "checkout.session.completed", "checkout.session.async_payment_succeeded"
      ledger_entry = LedgerEntry.where("metadata->'stripe_checkout_session'->>'id' = ?", event.data.object.id)
      ledger_entry.update(finalized: event.data.object.payment_status == "paid")
    when "checkout.session.expired", "checkout.session.async_payment_failed"
      ledger_entry = LedgerEntry.where("metadata->'stripe_checkout_session'->>'id' = ?", event.data.object.id)
      ledger_entry.update(failed: true)
    end
  end

  def finish_setup
    endpoint = Stripe::WebhookEndpoint.create({
      enabled_events: [ "checkout.session.completed", "checkout.session.async_payment_succeeded", "checkout.session.expired", "checkout.session.async_payment_failed" ],
      url: Rails.application.routes.url_helpers.webhook_gateway_url(self)
    },
    {
      api_key: secret_key
    }
    )

    update(secret: endpoint.secret)
  end

  def webhook_problem
    "not ready: no webhook signing secret" if secret.blank?
  end

  def entry_handler_url_for(entry)
    entry.metadata&.dig("stripe_checkout_session", "url")
  end
end
