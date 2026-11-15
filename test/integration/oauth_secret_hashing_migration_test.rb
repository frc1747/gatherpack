require "test_helper"
require Rails.root.join("db/migrate/20261029150000_hash_oauth_secrets")

# Rows written before secrets were hashed keep working once the migration
# has hashed them.
class OauthSecretHashingMigrationTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @user = User.create!(email: "oauth-member@example.com", password: "Password1!")
    @app = OauthApplication.create!(name: "Legacy", redirect_uri: "https://legacy.example.com/callback", scopes: "user_read")
    @app.update_columns(secret: "plain-client-secret")
    @token = Doorkeeper::AccessToken.create!(resource_owner_id: @user.id, application_id: @app.id, scopes: "user_read",
                                             expires_in: 2.hours, use_refresh_token: true)
    @token.update_columns(token: "plain-access-token", refresh_token: "plain-refresh-token")
    @renewed = Doorkeeper::AccessToken.create!(resource_owner_id: @user.id, application_id: @app.id, scopes: "user_read",
                                               expires_in: 2.hours, use_refresh_token: true)
    @renewed.update_columns(token: "plain-renewed-token", refresh_token: "plain-renewed-refresh",
                            previous_refresh_token: "plain-refresh-token")
    @grant = Doorkeeper::AccessGrant.create!(resource_owner_id: @user.id, application_id: @app.id, scopes: "user_read",
                                             redirect_uri: @app.redirect_uri, expires_in: 10.minutes)
    @grant.update_columns(token: "plain-authorization-code")

    migrate
  end

  test "stores only hashes of existing secrets" do
    assert_equal sha256("plain-client-secret"), @app.reload.secret
    assert_equal sha256("plain-access-token"), @token.reload.token
    assert_equal sha256("plain-refresh-token"), @token.refresh_token
    assert_equal sha256("plain-refresh-token"), @renewed.reload.previous_refresh_token
    assert_equal sha256("plain-authorization-code"), @grant.reload.token
  end

  test "running it again leaves hashes alone" do
    migrate

    assert_equal sha256("plain-client-secret"), @app.reload.secret
    assert_equal sha256("plain-access-token"), @token.reload.token
  end

  test "a hashed client secret still authenticates" do
    post oauth_token_path, params: { grant_type: "client_credentials", client_id: @app.uid, client_secret: "plain-client-secret" }

    assert_response :success
  end

  test "an existing access token still works" do
    get "/api/v1/userinfo", headers: { Authorization: "Bearer plain-access-token" }

    assert_response :success
  end

  test "an existing refresh token still works" do
    post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: "plain-refresh-token",
                                     client_id: @app.uid, client_secret: "plain-client-secret" }

    assert_response :success
  end

  test "using a renewed token still revokes the refresh token it replaced" do
    get "/api/v1/userinfo", headers: { Authorization: "Bearer plain-renewed-token" }

    assert_response :success
    assert @token.reload.revoked?
  end

  test "an existing authorization code can still be redeemed" do
    post oauth_token_path, params: { grant_type: "authorization_code", code: "plain-authorization-code", client_id: @app.uid,
                                     client_secret: "plain-client-secret", redirect_uri: @app.redirect_uri }

    assert_response :success
  end

  private

  def migrate
    ActiveRecord::Migration.suppress_messages { HashOauthSecrets.new.migrate(:up) }
  end

  def sha256(value)
    Digest::SHA256.hexdigest(value)
  end
end
