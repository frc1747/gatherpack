require "test_helper"
require "rake"

class GatewaysRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("gateways:scrub_audit_log")
    Rake::Task["gateways:scrub_audit_log"].reenable
    Rake::Task["gateways:reencrypt"].reenable
  end

  test "scrub_audit_log removes secrets from old gateway audit log rows" do
    gateway = Gateway::StripeGateway.create!(name: "Stripe", public_key: "pk_live_x")
    old_configuration = { "public_key" => "pk_live_x", "secret_key" => "sk_live_OLDROW", "secret" => "whsec_OLDROW" }.to_json
    log = AuditLog.create!(item_type: "Gateway", item_id: gateway.id, event: "update",
      object: PaperTrail.serializer.dump("id" => gateway.id, "name" => "Stripe", "configuration" => old_configuration),
      object_changes: PaperTrail.serializer.dump("configuration" => [ { "public_key" => "pk_live_x" }.to_json, old_configuration ]))
    other = AuditLog.create!(item_type: "Variable", item_id: gateway.id, event: "update",
      object: PaperTrail.serializer.dump("configuration" => old_configuration))

    assert_output(/Removed gateway secrets from 1 audit log row\./) do
      Rake::Task["gateways:scrub_audit_log"].invoke
    end

    log.reload
    rows = [ log.object, log.object_changes ].join("\n")
    assert_not_includes rows, "sk_live_OLDROW"
    assert_not_includes rows, "whsec_OLDROW"
    assert_equal({ "public_key" => "pk_live_x" }, JSON.parse(PaperTrail.serializer.load(log.object)["configuration"]))
    assert_equal "Stripe", PaperTrail.serializer.load(log.object)["name"]
    assert_includes other.reload.object, "sk_live_OLDROW", "rows of other models were changed"
  end

  test "reencrypt encrypts readable gateway secrets again and skips unreadable ones" do
    readable = Gateway::StripeGateway.create!(name: "Readable", secret_key: "sk_live_READABLE")
    unreadable = Gateway::StripeGateway.create!(name: "Unreadable", secret_key: "sk_live_x")
    unreadable_ciphertext = ActiveRecord::Encryption::Encryptor.new.encrypt({ secret_key: "sk_live_x" }.to_json,
      key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("a key this install doesn't have"))
    Gateway.where(id: unreadable.id).update_all([ "secrets = ?", unreadable_ciphertext ])
    readable_ciphertext = raw_secrets(readable)

    assert_output(/Skipped Gateway::StripeGateway##{unreadable.id} \(Unreadable\).*Re-encrypted the secrets of \d+ gateways?\./m) do
      Rake::Task["gateways:reencrypt"].invoke
    end

    assert_not_equal readable_ciphertext, raw_secrets(readable)
    assert_equal "sk_live_READABLE", Gateway.find(readable.id).secret_key
    assert_equal unreadable_ciphertext, raw_secrets(unreadable)
  end

  private
    def raw_secrets(gateway)
      Gateway.connection.select_value(Gateway.sanitize_sql([ "SELECT secrets FROM gateways WHERE id = ?", gateway.id ]))
    end
end
