require "test_helper"

class OauthPkceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  REDIRECT_URI = "https://client.example.com/callback".freeze

  setup do
    host! "localhost"
    @user = User.create!(email: "oauth-member@example.com", password: "Password1!")
    Person.create!(user: @user, first_name: "Test", last_name: "Member")
  end

  test "PKCE (S256) is supported" do
    assert_includes Doorkeeper.config.pkce_code_challenge_methods_supported, "S256",
      "PKCE is unsupported: oauth_access_grants lacks code_challenge columns, so code_challenge is ignored"
  end

  test "the plain challenge method is refused" do
    app = create_app(confidential: false)
    sign_in @user

    post oauth_authorization_path, params: { client_id: app.uid, redirect_uri: REDIRECT_URI, response_type: "code",
                                             scope: "user_read", state: "s", code_challenge: "x",
                                             code_challenge_method: "plain" }

    assert_response :redirect
    assert_equal "invalid_code_challenge_method", query(response.location)["error"]
    assert_nil query(response.location)["code"], "a code was issued for a plain PKCE challenge"
  end

  test "a public client cannot redeem an authorization code without PKCE" do
    app = create_app(confidential: false)
    grant = Doorkeeper::AccessGrant.create!(resource_owner_id: @user.id, application_id: app.id, redirect_uri: REDIRECT_URI,
                                            scopes: "user_read", expires_in: 10.minutes)

    post oauth_token_path, params: { grant_type: "authorization_code", code: grant.plaintext_token, client_id: app.uid,
                                     redirect_uri: REDIRECT_URI }

    assert_not_equal 200, response.status,
      "public client redeemed a code with no secret and no code_verifier (PKCE not required): got #{response.parsed_body.keys}"
  end

  test "a public client gets no code without a code challenge" do
    app = create_app(confidential: false)
    sign_in @user

    post oauth_authorization_path, params: { client_id: app.uid, redirect_uri: REDIRECT_URI, response_type: "code",
                                             scope: "user_read", state: "s" }

    assert_response :redirect
    assert_equal "invalid_request", query(response.location)["error"]
    assert_nil query(response.location)["code"], "a public client was issued a code without PKCE"
  end

  test "a public client with the wrong verifier gets no token" do
    app = create_app(confidential: false)
    verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    sign_in @user

    post oauth_authorization_path, params: { client_id: app.uid, redirect_uri: REDIRECT_URI, response_type: "code",
                                             scope: "user_read", state: "s", code_challenge: challenge,
                                             code_challenge_method: "S256" }
    code = query(response.location)["code"]
    assert code.present?, "consent issued no code (#{response.status} #{response.location})"
    sign_out :user

    post oauth_token_path, params: { grant_type: "authorization_code", code: code, client_id: app.uid,
                                     redirect_uri: REDIRECT_URI, code_verifier: "wrong-#{verifier}" }
    assert_not_equal 200, response.status, "a wrong code_verifier was accepted"
  end

  test "a public client with a correct S256 verifier gets a token" do
    app = create_app(confidential: false)
    verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    sign_in @user

    post oauth_authorization_path, params: { client_id: app.uid, redirect_uri: REDIRECT_URI, response_type: "code",
                                             scope: "user_read", state: "s", code_challenge: challenge,
                                             code_challenge_method: "S256" }
    code = query(response.location)["code"]
    sign_out :user

    post oauth_token_path, params: { grant_type: "authorization_code", code: code, client_id: app.uid,
                                     redirect_uri: REDIRECT_URI, code_verifier: verifier }

    assert_response :success
    assert response.parsed_body["access_token"].present?
  end

  test "a confidential client with its secret still needs no PKCE" do
    app = create_app(confidential: true)
    sign_in @user

    post oauth_authorization_path, params: { client_id: app.uid, redirect_uri: REDIRECT_URI, response_type: "code",
                                             scope: "user_read", state: "s" }
    code = query(response.location)["code"]
    assert code.present?, "consent issued no code (#{response.status} #{response.location})"
    sign_out :user

    post oauth_token_path, params: { grant_type: "authorization_code", code: code, client_id: app.uid,
                                     client_secret: app.plaintext_secret, redirect_uri: REDIRECT_URI }

    assert_response :success
    assert response.parsed_body["access_token"].present?
  end

  private

  def create_app(confidential:)
    OauthApplication.create!(name: "Client", redirect_uri: REDIRECT_URI, confidential: confidential, scopes: "user_read")
  end

  def query(location)
    Rack::Utils.parse_query(URI(location).query)
  end
end
