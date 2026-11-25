require "test_helper"

class GatewayTest < ActiveSupport::TestCase
  SECRET_KEY = "sk_live_TESTSECRETKEY".freeze
  WEBHOOK_SECRET = "whsec_TESTWEBHOOKSECRET".freeze

  test "gateways that don't receive webhooks refuse every webhook request" do
    [ Gateway::SmtpSendingGateway.new, Gateway::PostmarkSendingGateway.new(api_token: "pm-token") ].each do |gateway|
      assert_not gateway.verify_webhook("{}", {}), "#{gateway.class} accepted a webhook request"
    end
  end

  test "gateway secrets are not stored in plain text in the gateways table" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    gateway.update!(secret: WEBHOOK_SECRET)

    raw = Gateway.connection.select_one(
      Gateway.sanitize_sql([ "SELECT * FROM gateways WHERE id = ?", gateway.id ])).values.join("\n")

    assert_not_includes raw, SECRET_KEY, "gateways.configuration holds the live Stripe secret key in plain text"
    assert_not_includes raw, WEBHOOK_SECRET
    assert_equal SECRET_KEY, gateway.reload.secret_key
    assert_equal WEBHOOK_SECRET, gateway.secret
  end

  test "gateway secrets are not copied into the audit log" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    gateway.update!(secret: WEBHOOK_SECRET, public_key: "pk_live_y")
    gateway.update!(secret_key: "sk_live_ROTATED")

    rows = AuditLog.where(item_id: gateway.id).pluck(:object, :object_changes).flatten.compact.join("\n")

    assert_not rows.include?(SECRET_KEY), "audit_logs (PaperTrail on Gateway) contains the Stripe secret key"
    assert_not rows.include?(WEBHOOK_SECRET), "audit_logs (PaperTrail on Gateway) contains the Stripe webhook signing secret"
    assert_not rows.include?("sk_live_ROTATED")
    assert_includes rows, "pk_live_y"
  end

  test "reverting a gateway to an audit log row keeps its secrets" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    gateway.update!(name: "Renamed")

    gateway.versions.where(event: "update").last.reify.save!

    gateway.reload
    assert_equal "Stripe", gateway.name
    assert_equal SECRET_KEY, gateway.secret_key
  end

  test "reverting to an audit log row written before secrets were encrypted doesn't bring them back" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    legacy_configuration = { "public_key" => "pk_live_old", "secret_key" => "sk_live_LEGACY", "secret" => "whsec_LEGACY" }.to_json
    legacy = AuditLog.create!(item_type: "Gateway", item_id: gateway.id, event: "update",
      object: PaperTrail.serializer.dump(gateway.attributes.except("secrets").merge("configuration" => legacy_configuration)))

    legacy.reify.save!

    raw = Gateway.connection.select_one(
      Gateway.sanitize_sql([ "SELECT * FROM gateways WHERE id = ?", gateway.id ])).values.join("\n")
    assert_not_includes raw, "sk_live_LEGACY", "a revert wrote an old secret back into gateways.configuration"
    assert_not_includes raw, "whsec_LEGACY"

    rows = AuditLog.where(item_id: gateway.id).where.not(id: legacy.id).pluck(:object, :object_changes).flatten.compact.join("\n")
    assert_not_includes rows, "sk_live_LEGACY", "a revert copied an old secret into a new audit log row"

    gateway.reload
    assert_equal "pk_live_old", gateway.public_key
    assert_equal SECRET_KEY, gateway.secret_key
  end

  test "reverting a gateway whose secrets can't be decrypted keeps the stored secrets" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    gateway.update!(name: "Renamed")
    unreadable = ActiveRecord::Encryption::Encryptor.new.encrypt({ secret_key: SECRET_KEY }.to_json,
      key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("a key this install doesn't have"))
    Gateway.where(id: gateway.id).update_all([ "secrets = ?", unreadable ])

    gateway.versions.where(event: "update").last.reify.save!

    assert_equal "Stripe", Gateway.find(gateway.id).name
    assert_equal unreadable, Gateway.connection.select_value(Gateway.sanitize_sql([ "SELECT secrets FROM gateways WHERE id = ?", gateway.id ]))
  end

  test "saving a gateway whose secrets can't be decrypted leaves the stored secrets alone" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    unreadable = ActiveRecord::Encryption::Encryptor.new.encrypt({ secret_key: SECRET_KEY }.to_json,
      key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("a key this install doesn't have"))
    Gateway.where(id: gateway.id).update_all([ "secrets = ?", unreadable ])

    gateway = Gateway.find(gateway.id)
    assert gateway.secrets_unreadable?
    assert_nil gateway.secret_key
    gateway.update!(name: "Renamed")
    gateway.save!

    assert_equal unreadable, Gateway.connection.select_value(Gateway.sanitize_sql([ "SELECT secrets FROM gateways WHERE id = ?", gateway.id ]))
  end

  test "a Stripe payment uses the stored secret key" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", secret_key: SECRET_KEY, public_key: "pk_live_x")
    payment = LedgerPayment.new(ledger_id: ledgers(:one).id, amount: 5, remark: "Dues")
    used_key = nil

    original_create = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) do |params, opts|
      used_key = opts[:api_key]
      Stripe::Checkout::Session.construct_from(id: "cs_test_payment", url: "https://checkout.stripe.com/c/pay/cs_test_payment")
    end

    begin
      entry = gateway.start_payment(payment, people(:one))
      assert_equal "cs_test_payment", entry.metadata.dig("stripe_checkout_session", "id")
    ensure
      Stripe::Checkout::Session.define_singleton_method(:create, original_create)
    end

    assert_equal SECRET_KEY, used_key
  end
end
