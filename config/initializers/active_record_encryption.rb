# Keys for Active Record encryption (`encrypts` in models). Each key is read
# from its environment variable when set:
#
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#
# Otherwise it is derived from secret_key_base, so an install needs no new
# secret. Changing secret_key_base (or a key variable) makes values encrypted
# under the old key unreadable, so keep it with the database backups. Keys in
# credentials (active_record_encryption.*) take precedence over both.
Rails.application.configure do
  derive = ->(purpose) { key_generator.generate_key("active_record_encryption #{purpose}", 32).unpack1("H*") }
  credentials_keys = credentials.active_record_encryption || {}
  encryption = config.active_record.encryption

  encryption.primary_key ||= credentials_keys[:primary_key] || ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || derive.call("primary key")
  encryption.deterministic_key ||= credentials_keys[:deterministic_key] || ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || derive.call("deterministic key")
  encryption.key_derivation_salt ||= credentials_keys[:key_derivation_salt] || ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || derive.call("key derivation salt")
end
