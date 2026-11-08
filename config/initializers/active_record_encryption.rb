# Keys for Active Record encryption (gateway secrets, secret settings).
#
# Each key comes from ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY,
# ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY and
# ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT, else from the
# active_record_encryption credentials (`bin/rails db:encryption:init`
# generates either), else it is derived from secret_key_base. See
# docs/self-hosting.md.
Rails.application.configure do
  derived_key = ->(name) { Rails.application.key_generator.generate_key("active_record_encryption/#{name}", 32).unpack1("H*") }
  explicit_key = lambda do |name|
    ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"].presence || Rails.application.credentials.dig(:active_record_encryption, name.to_sym).presence
  end

  keys = %w[primary_key deterministic_key key_derivation_salt].index_with { |name| explicit_key.call(name) || derived_key.call(name) }
  config.active_record.encryption.primary_key = keys["primary_key"]
  config.active_record.encryption.deterministic_key = keys["deterministic_key"]
  config.active_record.encryption.key_derivation_salt = keys["key_derivation_salt"]

  config.active_record.encryption.encrypt_fixtures = true

  # Secrets saved while the keys were derived stay readable after explicit
  # keys are set, and are re-encrypted with them when saved again. A
  # previous scheme needs a key provider rather than a password and salt,
  # so derive the key the way Active Record does.
  derived_primary_key = derived_key.call("primary_key")
  derived_salt = derived_key.call("key_derivation_salt")
  if keys["primary_key"] != derived_primary_key || keys["key_derivation_salt"] != derived_salt
    ActiveSupport.on_load(:active_record_encryption) do
      key = ActiveSupport::KeyGenerator.new(derived_primary_key, hash_digest_class: ActiveRecord::Encryption.config.hash_digest_class)
        .generate_key(derived_salt, ActiveRecord::Encryption.cipher.key_length)
      ActiveRecord::Encryption.config.previous = [ { key_provider: ActiveRecord::Encryption::KeyProvider.new(ActiveRecord::Encryption::Key.new(key)) } ]
    end
  end
end
