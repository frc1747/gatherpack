require "test_helper"

class GatewaysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
  end

  test "webhook only forwards the headers the gateway class declares" do
    gateway = gateway_stripe_gateways(:with_secret)
    signature = stripe_signature("{}", gateway.secret)

    assert_enqueued_with(job: ProcessGatewayWebhookJob) do
      post webhook_gateway_url(gateway), params: "{}", headers: {
        "HTTP_STRIPE_SIGNATURE" => signature,
        "HTTP_X_FORWARDED_FOR" => "1.2.3.4",
        "HTTP_COOKIE" => "session=super-secret"
      }
    end

    headers = enqueued_jobs.last[:args][2].except("_aj_symbol_keys")

    assert_equal [ "HTTP_STRIPE_SIGNATURE" ], headers.keys
    assert_equal signature, headers["HTTP_STRIPE_SIGNATURE"]
  end

  test "a webhook request with a bad Stripe signature is refused up front and not queued" do
    gateway = gateway_stripe_gateways(:with_secret)
    junk = { id: "evt_x", type: "checkout.session.completed", padding: "A" * 200_000 }.to_json

    post webhook_gateway_url(gateway), params: junk,
      headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => "t=1,v1=deadbeef" }

    assert_equal 0, enqueued_jobs.size,
      "An anonymous request with an invalid Stripe signature (200 KB body) was queued as a job (got HTTP #{response.status})"
    assert_response :bad_request
  end

  test "a correctly signed Stripe event is queued and marks the payment paid" do
    gateway = gateway_stripe_gateways(:with_secret)
    entry = pending_stripe_entry(gateway, "cs_test_signed")
    event = completed_checkout_event("cs_test_signed")

    perform_enqueued_jobs do
      post webhook_gateway_url(gateway), params: event,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => stripe_signature(event, gateway.secret) }
    end

    assert_response :no_content
    assert entry.reload.finalized
  end

  test "a webhook request over the size limit is refused and not queued" do
    gateway = gateway_stripe_gateways(:with_secret)
    body = { padding: "A" * GatewaysController::WEBHOOK_MAX_BYTES }.to_json

    post webhook_gateway_url(gateway), params: body,
      headers: { "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => stripe_signature(body, gateway.secret) }

    assert_response :content_too_large
    assert_no_enqueued_jobs
  end

  test "a gateway that doesn't receive webhooks refuses webhook requests" do
    gateway = Gateway::PostmarkSendingGateway.create!(name: "Postmark", api_token: "pm-token", sender: "team@example.com")
    clear_enqueued_jobs

    post webhook_gateway_url(gateway), params: "{}", headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_no_enqueued_jobs
  end

  test "an SMTP gateway refuses webhook requests" do
    gateway = Gateway::SmtpSendingGateway.create!(name: "SMTP", host: "smtp.example.com")
    clear_enqueued_jobs

    post webhook_gateway_url(gateway), params: "{}", headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_no_enqueued_jobs
  end

  test "webhook requests are rate limited per address" do
    gateway = gateway_stripe_gateways(:with_secret)
    store = ActiveSupport::Cache::MemoryStore.new
    limiter = GatewaysController.cache_store
    limiter.define_singleton_method(:increment) { |*args, **options| store.increment(*args, **options) }

    begin
      120.times { post webhook_gateway_url(gateway), params: "{}" }
      assert_response :bad_request

      post webhook_gateway_url(gateway), params: "{}"
      assert_response :too_many_requests
    ensure
      limiter.singleton_class.remove_method(:increment)
    end
  end

  test "an inbound Postmark request without credentials doesn't create a mailbox message" do
    gateway = Gateway::PostmarkReceivingGateway.create!(name: "Inbound", server_token: "pm-server-token")
    mailbox = Mailbox.create!(address: "team@inbound.example.com")

    perform_enqueued_jobs do
      post webhook_gateway_url(gateway), params: inbound_message("team@inbound.example.com"), headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_equal 0, mailbox.mailbox_messages.count,
      "An anonymous, unauthenticated POST to the Postmark receiving webhook planted a message with a spoofed From address into a team mailbox"
    assert_response :unauthorized
  end

  test "an inbound Postmark request with the wrong password is refused" do
    gateway = Gateway::PostmarkReceivingGateway.create!(name: "Inbound", server_token: "pm-server-token")
    mailbox = Mailbox.create!(address: "team@inbound.example.com")

    perform_enqueued_jobs do
      post webhook_gateway_url(gateway), params: inbound_message("team@inbound.example.com"),
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => basic_auth("postmark", "wrong-password") }
    end

    assert_response :unauthorized
    assert_equal 0, mailbox.mailbox_messages.count
  end

  test "an inbound Postmark request with the gateway's credentials creates the mailbox message" do
    gateway = Gateway::PostmarkReceivingGateway.create!(name: "Inbound", server_token: "pm-server-token")
    mailbox = Mailbox.create!(address: "team@inbound.example.com")

    perform_enqueued_jobs do
      post webhook_gateway_url(gateway), params: inbound_message("team@inbound.example.com"),
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => basic_auth("postmark", gateway.inbound_password) }
    end

    assert_response :no_content
    assert_equal [ "Hello" ], mailbox.mailbox_messages.pluck(:subject)
  end

  test "a Postmark receiving gateway without an inbound password refuses everything" do
    gateway = Gateway::PostmarkReceivingGateway.create!(name: "Inbound", server_token: "pm-server-token")
    gateway.update!(secrets: gateway.secrets.except("inbound_password"))
    clear_enqueued_jobs

    post webhook_gateway_url(gateway), params: inbound_message("team@inbound.example.com"),
      headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => basic_auth("postmark", "") }

    assert_response :unauthorized
    assert_no_enqueued_jobs
  end

  test "the gateway page shows the inbound URL with credentials and an architect can regenerate the password" do
    gateway = Gateway::PostmarkReceivingGateway.create!(name: "Inbound", server_token: "pm-server-token")
    old_password = gateway.inbound_password
    sign_in create_user("architect@example.com", admin: true, architect: true)

    get gateway_url(gateway)
    assert_response :success
    assert_includes response.body, "://postmark:#{old_password}@"

    patch gateway_url(gateway), params: { gateway: { regenerate_inbound_password: "1" } }
    assert_redirected_to gateway_url(gateway)
    assert_not_equal old_password, gateway.reload.inbound_password
    assert_predicate gateway.inbound_password, :present?
  end

  test "the edit form doesn't render stored secrets" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_live_EDITFORMSECRET", public_key: "pk_live_x", secret: "whsec_EDITFORMSECRET")
    sign_in create_user("architect@example.com", admin: true, architect: true)

    get edit_gateway_url(gateway)
    assert_response :success
    assert_not_includes response.body, "sk_live_EDITFORMSECRET"
    assert_not_includes response.body, "whsec_EDITFORMSECRET"
    assert_includes response.body, "pk_live_x"

    get gateway_url(gateway)
    assert_response :success
    assert_not_includes response.body, "sk_live_EDITFORMSECRET"
    assert_not_includes response.body, "whsec_EDITFORMSECRET"
  end

  test "saving the edit form with a blank secret keeps it, and a new one replaces it" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_live_OLD", public_key: "pk_live_x", secret: "whsec_OLD")
    sign_in create_user("architect@example.com", admin: true, architect: true)

    patch gateway_url(gateway), params: { gateway: { name: "Stripe", public_key: "pk_live_y", secret_key: "", secret: "whsec_NEW" } }

    gateway.reload
    assert_equal "pk_live_y", gateway.public_key
    assert_equal "sk_live_OLD", gateway.secret_key
    assert_equal "whsec_NEW", gateway.secret
  end

  test "a gateway whose secrets can't be decrypted still opens and takes new secrets" do
    gateway = unreadable_stripe_gateway
    sign_in create_user("architect@example.com", admin: true, architect: true)

    get gateway_url(gateway)
    assert_response :success
    assert_includes response.body, "secrets can't be decrypted"

    get edit_gateway_url(gateway)
    assert_response :success

    patch gateway_url(gateway), params: { gateway: { secret_key: "sk_live_NEW", secret: "whsec_NEW" } }
    assert_redirected_to gateway_url(gateway)

    gateway = Gateway.find(gateway.id)
    assert_equal "sk_live_NEW", gateway.secret_key
    assert_equal "whsec_NEW", gateway.secret
    assert_not gateway.secrets_unreadable?
  end

  test "a gateway whose secrets can't be decrypted can be renamed without losing the stored secrets" do
    gateway = unreadable_stripe_gateway
    ciphertext = raw_secrets(gateway)
    sign_in create_user("architect@example.com", admin: true, architect: true)

    patch gateway_url(gateway), params: { gateway: { name: "Renamed", public_key: "pk_live_y", secret_key: "", secret: "" } }

    assert_redirected_to gateway_url(gateway)
    assert_equal "Renamed", gateway.reload.name
    assert_equal ciphertext, raw_secrets(gateway), "saving other fields replaced the stored secrets"
  end

  test "a gateway whose secrets can't be decrypted can be deleted" do
    gateway = unreadable_stripe_gateway
    sign_in create_user("architect@example.com", admin: true, architect: true)

    delete gateway_url(gateway)

    assert_redirected_to gateways_url
    assert_not Gateway.exists?(gateway.id)
  end

  test "an architect can clear secrets that can't be decrypted" do
    gateway = unreadable_stripe_gateway
    sign_in create_user("architect@example.com", admin: true, architect: true)

    get gateway_url(gateway)
    assert_includes response.body, "Clear unreadable secrets"

    patch gateway_url(gateway), params: { clear_unreadable_secrets: "1" }

    assert_redirected_to edit_gateway_url(gateway)
    assert_nil raw_secrets(gateway)
    assert_not Gateway.find(gateway.id).secrets_unreadable?
  end

  test "clearing readable secrets does nothing, and only architects can clear secrets" do
    gateway = gateway_stripe_gateways(:with_secret)
    ciphertext = raw_secrets(gateway)

    sign_in create_user("admin@example.com", admin: true)
    patch gateway_url(gateway), params: { clear_unreadable_secrets: "1" }
    assert_equal ciphertext, raw_secrets(gateway)

    unreadable = unreadable_stripe_gateway
    unreadable_ciphertext = raw_secrets(unreadable)
    patch gateway_url(unreadable), params: { clear_unreadable_secrets: "1" }
    assert_equal unreadable_ciphertext, raw_secrets(unreadable), "a non-architect cleared a gateway's secrets"

    sign_in create_user("architect@example.com", admin: true, architect: true)
    patch gateway_url(gateway), params: { clear_unreadable_secrets: "1" }
    assert_redirected_to gateway_url(gateway)
    assert_equal ciphertext, raw_secrets(gateway)
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
    # A Stripe gateway whose secrets were encrypted with keys this install
    # doesn't have.
    def unreadable_stripe_gateway
      gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: "sk_live_OLD", public_key: "pk_live_x", secret: "whsec_OLD")
      other_keys = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("a key this install doesn't have")
      unreadable = ActiveRecord::Encryption::Encryptor.new.encrypt({ secret_key: "sk_live_OLD" }.to_json, key_provider: other_keys)
      Gateway.where(id: gateway.id).update_all([ "secrets = ?", unreadable ])
      gateway
    end

    def raw_secrets(gateway)
      Gateway.connection.select_value(Gateway.sanitize_sql([ "SELECT secrets FROM gateways WHERE id = ?", gateway.id ]))
    end

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

    def stripe_signature(payload, secret)
      timestamp = Time.now
      Stripe::Webhook::Signature.generate_header(timestamp, Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret))
    end

    def basic_auth(user, password)
      ActionController::HttpAuthentication::Basic.encode_credentials(user, password)
    end

    def inbound_message(to)
      {
        FromFull: { Email: "someone@example.com" },
        ToFull: [ { Email: to } ], CcFull: [], BccFull: [],
        Subject: "Hello", HtmlBody: "<p>Hi</p>"
      }.to_json
    end

    def completed_checkout_event(session_id)
      {
        id: "evt_test", object: "event", type: "checkout.session.completed",
        data: { object: { id: session_id, object: "checkout.session", payment_status: "paid" } }
      }.to_json
    end
end
