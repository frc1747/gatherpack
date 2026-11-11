require "test_helper"

class OauthRefreshTokenTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @user = User.create!(email: "oauth-member@example.com", password: "Password1!")
    @app = OauthApplication.create!(name: "Client", redirect_uri: "https://client.example.com/callback", scopes: "user_read")
    @token = Doorkeeper::AccessToken.create!(resource_owner_id: @user.id, application_id: @app.id,
                                             scopes: "user_read", expires_in: 2.hours, use_refresh_token: true)
  end

  test "a refresh token stops working after a reasonable lifetime" do
    travel 2.years do
      refresh(@token.plaintext_refresh_token)

      assert_not_equal 200, response.status, "a two-year-old refresh token still mints a new access token: #{response.body[0, 120]}"
    end
  end

  test "a refresh token works until the end of its lifetime" do
    travel 29.days do
      refresh(@token.plaintext_refresh_token)

      assert_response :success
    end

    travel 31.days do
      refresh(@token.plaintext_refresh_token)

      assert_response :bad_request
      assert_equal "invalid_grant", response.parsed_body["error"]
    end
  end

  test "control: a fresh refresh token works right away" do
    refresh(@token.plaintext_refresh_token)

    assert_equal 200, response.status, response.body[0, 200]
  end

  test "using a refresh token issues one with a fresh lifetime" do
    travel 20.days
    refresh(@token.plaintext_refresh_token)
    assert_response :success
    renewed = response.parsed_body["refresh_token"]

    travel 20.days
    refresh(renewed)

    assert_response :success
  end

  private

  def refresh(refresh_token)
    post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: refresh_token,
                                     client_id: @app.uid, client_secret: @app.plaintext_secret }
  end
end
