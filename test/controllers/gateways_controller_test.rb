require "test_helper"

class GatewaysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
  end

  test "webhook only forwards the headers the gateway class declares" do
    gateway = gateway_stripe_gateways(:with_secret)

    assert_enqueued_with(job: ProcessGatewayWebhookJob) do
      post webhook_gateway_url(gateway), params: "{}", headers: {
        "HTTP_STRIPE_SIGNATURE" => "t=123,v1=abc",
        "HTTP_X_FORWARDED_FOR" => "1.2.3.4",
        "HTTP_COOKIE" => "session=super-secret"
      }
    end

    headers = enqueued_jobs.last[:args][2].except("_aj_symbol_keys")

    assert_equal [ "HTTP_STRIPE_SIGNATURE" ], headers.keys
    assert_equal "t=123,v1=abc", headers["HTTP_STRIPE_SIGNATURE"]
  end

  test "an unsigned Stripe event doesn't mark a payment paid when the gateway has no webhook secret" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_test_x", public_key: "pk_test_x")
    clear_enqueued_jobs
    entry = pending_stripe_entry(gateway, "cs_test_unsigned")

    perform_enqueued_jobs do
      post webhook_gateway_url(gateway), params: completed_checkout_event("cs_test_unsigned"), headers: { "CONTENT_TYPE" => "application/json" }
    rescue StandardError
      nil
    end

    assert_not entry.reload.finalized,
      "An anonymous, unsigned POST to the Stripe webhook marked a pending ledger entry as paid (no Stripe-Signature check when secret is blank)"
  end

  test "a forged Stripe event doesn't mark a payment paid when the gateway has a webhook secret" do
    gateway = gateway_stripe_gateways(:with_secret)
    entry = pending_stripe_entry(gateway, "cs_test_forged")

    perform_enqueued_jobs do
      post webhook_gateway_url(gateway), params: completed_checkout_event("cs_test_forged"),
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => "t=1,v1=deadbeef" }
    rescue StandardError
      nil
    end

    assert_not entry.reload.finalized
  end

  test "the gateway page says a Stripe gateway without a webhook secret isn't ready" do
    sign_in create_user("architect@example.com", admin: true, architect: true)

    get gateway_url(gateway_stripe_gateways(:without_secret))
    assert_response :success
    assert_includes response.body, "not ready: no webhook signing secret"

    get gateway_url(gateway_stripe_gateways(:with_secret))
    assert_response :success
    assert_not_includes response.body, "not ready"
  end

  private
    def create_user(email, **flags)
      user = User.create!(email: email, password: "Password1!", **flags)
      Person.create!(user: user, first_name: "Test", last_name: "Person")
      user
    end

    # A pending entry as Gateway::StripeGateway#start_payment leaves it,
    # without calling Stripe.
    def pending_stripe_entry(gateway, session_id)
      LedgerEntry.create!(ledger: ledgers(:one), amount: 5, finalized: false, created_by: people(:one),
        remark: "Paid via Stripe | dues",
        metadata: { gateway_id: gateway.id, stripe_checkout_session: { id: session_id, url: "https://checkout.stripe.com/c/pay/#{session_id}" } })
    end

    def completed_checkout_event(session_id)
      {
        id: "evt_test", object: "event", type: "checkout.session.completed",
        data: { object: { id: session_id, object: "checkout.session", payment_status: "paid" } }
      }.to_json
    end
end
