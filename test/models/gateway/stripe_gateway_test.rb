require "test_helper"

class Gateway::StripeGatewayTest < ActiveSupport::TestCase
  setup do
    @gateway = gateway_stripe_gateways(:with_secret)
    @payload = { id: "evt_test", type: "checkout.session.expired", data: { object: { id: "cs_test123" } } }.to_json
  end

  test "webhook_headers returns the stripe signature header name" do
    assert_equal [ "HTTP_STRIPE_SIGNATURE" ], Gateway::StripeGateway.webhook_headers
  end

  test "handle_webhook verifies a valid signature via the headers hash" do
    timestamp = Time.now
    signed = Stripe::Webhook::Signature.compute_signature(timestamp, @payload, @gateway.secret)
    header = Stripe::Webhook::Signature.generate_header(timestamp, signed)

    assert_nothing_raised do
      @gateway.handle_webhook(@payload, { "HTTP_STRIPE_SIGNATURE" => header })
    end
  end

  test "handle_webhook raises when the signature in the headers hash is invalid" do
    timestamp = Time.now
    signed = Stripe::Webhook::Signature.compute_signature(timestamp, @payload, "wrong_secret")
    header = Stripe::Webhook::Signature.generate_header(timestamp, signed)

    assert_raises(RuntimeError) do
      @gateway.handle_webhook(@payload, { "HTTP_STRIPE_SIGNATURE" => header })
    end
  end

  test "handle_webhook refuses every event when secret is blank" do
    gateway = gateway_stripe_gateways(:without_secret)
    entry = LedgerEntry.create!(ledger: ledgers(:one), amount: 5, finalized: false, created_by: people(:one),
      metadata: { gateway_id: gateway.id, stripe_checkout_session: { id: "cs_test123" } })

    gateway.handle_webhook(@payload, { "HTTP_STRIPE_SIGNATURE" => nil })

    assert_not entry.reload.failed, "an event was processed without a signature check"
  end
end
