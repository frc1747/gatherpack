require "test_helper"

class OauthSecretsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "oauth-member@example.com", password: "Password1!")
    @app = OauthApplication.create!(name: "Client", redirect_uri: "https://client.example.com/callback", scopes: "user_read")
  end

  test "access and refresh tokens are not stored in a usable form" do
    token = Doorkeeper::AccessToken.create!(resource_owner_id: @user.id, application_id: @app.id,
                                            scopes: "user_read", expires_in: 2.hours, use_refresh_token: true)
    row = stored_row("oauth_access_tokens", token.id, "token", "refresh_token")

    assert_not_equal token.plaintext_token, row["token"], "the bearer token is stored in clear in oauth_access_tokens.token"
    assert_not_equal token.plaintext_refresh_token, row["refresh_token"],
      "the refresh token is stored in clear in oauth_access_tokens.refresh_token"
  end

  test "authorization codes are not stored in a usable form" do
    grant = Doorkeeper::AccessGrant.create!(resource_owner_id: @user.id, application_id: @app.id, scopes: "user_read",
                                            redirect_uri: @app.redirect_uri, expires_in: 10.minutes)

    assert_not_equal grant.plaintext_token, stored_row("oauth_access_grants", grant.id, "token")["token"],
      "the authorization code is stored in clear in oauth_access_grants.token"
  end

  test "client secrets are not stored in a usable form" do
    assert_not_equal @app.plaintext_secret, stored_row("oauth_applications", @app.id, "secret")["secret"],
      "the client secret is stored in clear in oauth_applications.secret"
  end

  private

  def stored_row(table, id, *columns)
    connection = ActiveRecord::Base.connection
    connection.select_one("SELECT #{columns.join(', ')} FROM #{table} WHERE id = #{connection.quote(id)}")
  end
end
