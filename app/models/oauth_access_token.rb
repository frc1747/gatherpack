class OauthAccessToken < Doorkeeper::AccessToken
  # Doorkeeper never expires refresh tokens. Each refresh issues a new one, so
  # this limits how long a client can go without refreshing (and how long a
  # leaked refresh token stays useful) rather than how long it stays signed in.
  REFRESH_TOKEN_LIFETIME = 30.days

  def self.by_refresh_token(refresh_token)
    token = super
    token unless token&.refresh_token_expired?
  end

  def refresh_token_expired?
    created_at <= REFRESH_TOKEN_LIFETIME.ago
  end
end
