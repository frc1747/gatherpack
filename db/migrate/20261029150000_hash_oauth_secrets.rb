# OAuth tokens, authorization codes and client secrets used to be stored in
# clear. Doorkeeper now stores only their SHA-256 hashes (hash_token_secrets,
# hash_application_secrets), so hash the existing values the same way and they
# keep working without a plain-text fallback.
class HashOauthSecrets < ActiveRecord::Migration[8.1]
  class AccessToken < ActiveRecord::Base
    self.table_name = "oauth_access_tokens"
  end

  class AccessGrant < ActiveRecord::Base
    self.table_name = "oauth_access_grants"
  end

  class Application < ActiveRecord::Base
    self.table_name = "oauth_applications"
  end

  # Generated values are 43-character URL-safe Base64, so a 64-character hex
  # value is already a hash (rows written by the new code).
  HASHED = /\A\h{64}\z/

  def up
    hash_column AccessToken, :token
    hash_column AccessToken, :refresh_token
    # Holds the replaced token's stored refresh_token, so it must match it.
    hash_column AccessToken, :previous_refresh_token
    hash_column AccessGrant, :token
    hash_column Application, :secret
  end

  # Hashes can't be turned back into the values they came from. Reverting the
  # code that reads them means members authorize their apps again and admins
  # regenerate client secrets.
  def down
  end

  private

  def hash_column(model, column)
    model.where.not(column => [ nil, "" ]).find_each do |record|
      value = record[column]
      next if value.match?(HASHED)

      record.update_columns(column => Doorkeeper::SecretStoring::Sha256Hash.transform_secret(value))
    end
  end
end
