# Keys for Active Record encryption (`encrypts` in models; today only
# membership intake's entries and household rows). Each key comes from,
# in order:
#
#   1. credentials: active_record_encryption.primary_key,
#      .deterministic_key, .key_derivation_salt
#   2. the environment: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY,
#      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY,
#      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#   3. otherwise, derived from secret_key_base, so an install needs no new
#      secret to deploy.
#
# What the fallback means: the encrypted values can only be read with the
# secret_key_base (or keys) they were written with. Rotating
# secret_key_base without setting the three keys first makes every stored
# entry email, entry fact and guardian request unreadable; restoring a
# database backup needs the secret_key_base of its day. The data is
# short-lived (unfinished sign-ups are deleted after intake_entry_days), so
# the loss is pending sign-ups, not people or logins. To rotate
# secret_key_base safely, first set the three variables to the values this
# fallback derives (bin/rails runner 'p ActiveRecord::Encryption.config.primary_key'
# and the other two), then rotate.
#
# In development and test, secret_key_base is random per boot unless
# SECRET_KEY_BASE is set, so encrypted rows from an earlier boot can't be read.
Rails.application.configure do
  derive = ->(purpose) { key_generator.generate_key("active_record_encryption #{purpose}", 32).unpack1("H*") }
  credentials_keys = credentials.active_record_encryption || {}
  encryption = config.active_record.encryption

  encryption.primary_key ||= credentials_keys[:primary_key] || ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || derive.call("primary key")
  encryption.deterministic_key ||= credentials_keys[:deterministic_key] || ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || derive.call("deterministic key")
  encryption.key_derivation_salt ||= credentials_keys[:key_derivation_salt] || ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || derive.call("key derivation salt")
end
