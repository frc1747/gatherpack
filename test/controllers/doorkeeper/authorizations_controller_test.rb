require "test_helper"

class Doorkeeper::AuthorizationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @user = users(:one)
    @user.person.update!(first_name: "Ada", last_name: "Lovelace")
    @application = OauthApplication.create!(
      name: "Client App",
      redirect_uri: "https://one.example.com/callback\nhttps://two.example.com/callback https://three.example.com/callback",
      scopes: "user_read"
    )
  end

  test "consent page names the signed-in account" do
    sign_in @user
    get authorize_path("https://one.example.com/callback")

    assert_response :success
    assert_select "p", text: "Signed in as #{@user.person.display_name} (#{@user.email})"
  end

  test "consent page falls back to the email when the account has no person" do
    user = User.create!(email: "no-person@example.com", password: "Password1!")
    sign_in user
    get authorize_path("https://one.example.com/callback")

    assert_response :success
    assert_select "p", text: "Signed in as #{user.email}"
  end

  test "several redirect URIs separated by a new line or a space are all usable" do
    sign_in @user

    %w[https://one.example.com/callback https://two.example.com/callback https://three.example.com/callback].each do |uri|
      get authorize_path(uri)

      assert_response :success
      assert_select "form input[name=redirect_uri][value=?]", uri, minimum: 1
    end
  end

  test "an application already without scopes still authorizes until it's edited" do
    @application.update_columns(scopes: "")
    sign_in @user

    get authorize_path("https://one.example.com/callback")
    assert_response :success

    assert_difference -> { Doorkeeper::AccessGrant.count } do
      post oauth_authorization_path, params: {
        client_id: @application.uid, redirect_uri: "https://one.example.com/callback", response_type: "code", scope: "user_read"
      }
    end
    assert_match %r{\Ahttps://one\.example\.com/callback\?code=}, response.location
  end

  test "a redirect URI that isn't registered is refused" do
    sign_in @user
    get authorize_path("https://evil.example.com/callback")

    assert_select "input[name=redirect_uri]", count: 0
    assert_select "form[action=?]", oauth_authorization_path, count: 0
  end

  test "a signed-out visit comes back to the same request after signing in" do
    request_path = authorize_path("https://one.example.com/callback", state: "abc 123", code_challenge: "xyz", code_challenge_method: "S256")
    user = User.create!(email: "returning@example.com", password: "Password1!")

    get request_path
    assert_redirected_to new_user_session_url

    post user_session_path, params: { user: { email: user.email, password: "Password1!" } }
    assert_redirected_to "http://localhost#{request_path}"

    follow_redirect!
    assert_response :success
    assert_select "p", text: "Signed in as #{user.email}"
    assert_select "form[action=?][method=post] input[name=state][value=?]", oauth_authorization_path, "abc 123"
    assert_select "form[action=?][method=post] input[name=client_id][value=?]", oauth_authorization_path, @application.uid
  end

  test "a signed-out visit comes back to the same request after signing in with a provider" do
    request_path = authorize_path("https://one.example.com/callback", state: "abc123")
    user = User.create!(email: "provider@example.com", password: "Password1!", provider: "discord", uid: "provider-uid")
    auth = OmniAuth::AuthHash.new(provider: "discord", uid: "provider-uid", info: { email: user.email, first_name: "Pro", last_name: "Vider" })

    get request_path
    assert_redirected_to new_user_session_url

    get "/users/auth/discord/callback", env: { "omniauth.auth" => auth }
    assert_redirected_to "http://localhost#{request_path}"
  end

  test "signing in without an authorization request still goes home" do
    user = User.create!(email: "plain@example.com", password: "Password1!")

    post user_session_path, params: { user: { email: user.email, password: "Password1!" } }

    assert_redirected_to root_url
  end

  test "a signed-out POST to the endpoint isn't stored as a return location" do
    user = User.create!(email: "poster@example.com", password: "Password1!")

    post oauth_authorization_path, params: { client_id: @application.uid }
    assert_redirected_to new_user_session_url

    post user_session_path, params: { user: { email: user.email, password: "Password1!" } }
    assert_redirected_to root_url
  end

  test "the limit counts the bytes stored, not the bytes in the link" do
    fits = authorize_path_stored_at(OauthAuthorizationReturn::MAX_STORED_BYTES)
    too_long = authorize_path_stored_at(OauthAuthorizationReturn::MAX_STORED_BYTES + 1)

    assert OauthAuthorizationReturn.accepts?(fits)
    assert_not OauthAuthorizationReturn.accepts?(too_long)
    assert_not OauthAuthorizationReturn.accepts?("#{oauth_authorization_path}?#{"&" * 800}")
    assert_not OauthAuthorizationReturn.accepts?("#{oauth_authorization_path}?x=\xFF")
  end

  test "a link that would overflow the session cookie still reaches sign-in" do
    user = User.create!(email: "ampersands@example.com", password: "Password1!")

    [ "&k=v" * 300, "&" * 800 ].each do |junk|
      get "#{authorize_path("https://one.example.com/callback")}#{junk}"

      assert_redirected_to new_user_session_url
      assert_session_cookie_fits
    end

    post user_session_path, params: { user: { email: user.email, password: "Password1!" } }
    assert_redirected_to root_url
  end

  test "a link just under the limit returns after signing in" do
    user = User.create!(email: "just-under@example.com", password: "Password1!")

    [ :state, :ampersands ].each do |padding|
      request_path = authorize_path_stored_at(OauthAuthorizationReturn::MAX_STORED_BYTES, padding: padding)

      get request_path
      assert_redirected_to new_user_session_url
      assert_session_cookie_fits

      post user_session_path, params: { user: { email: user.email, password: "Password1!" } }
      assert_redirected_to "http://localhost#{request_path}"
      assert_session_cookie_fits

      sign_out user
    end
  end

  test "a link just under the limit returns through the different-account control" do
    other = User.create!(email: "just-under-other@example.com", password: "Password1!")
    request_path = authorize_path_stored_at(OauthAuthorizationReturn::MAX_STORED_BYTES, padding: :ampersands)
    sign_in @user

    delete destroy_user_session_path, params: { oauth_return_to: request_path }
    assert_redirected_to "http://localhost#{request_path}"
    assert_session_cookie_fits

    follow_redirect!
    assert_redirected_to new_user_session_url
    assert_session_cookie_fits

    post user_session_path, params: { user: { email: other.email, password: "Password1!" } }
    assert_redirected_to "http://localhost#{request_path}"
  end

  test "an authorization request too long for the session isn't stored" do
    long_path = authorize_path_stored_at(OauthAuthorizationReturn::MAX_STORED_BYTES + 1)
    user = User.create!(email: "long@example.com", password: "Password1!")

    get long_path
    assert_redirected_to new_user_session_url

    post user_session_path, params: { user: { email: user.email, password: "Password1!" } }
    assert_redirected_to root_url
  end

  test "the different-account control signs out with a valid token and returns to the request" do
    request_path = authorize_path("https://one.example.com/callback", state: "abc 123")
    other = User.create!(email: "other-account@example.com", password: "Password1!")

    with_forgery_protection do
      sign_in @user
      get request_path
      assert_response :success

      form = css_select("form[action='#{destroy_user_session_path}']").first
      assert_equal "false", form["data-turbo"]
      assert_equal "delete", form.at_css("input[name=_method]")["value"]
      assert_includes form.at_css("input[type=submit]")["value"], "Use a different account"
      assert_equal request_path, form.at_css("input[name=oauth_return_to]")["value"]
      token = form.at_css("input[name=authenticity_token]")["value"]

      delete destroy_user_session_path, params: { authenticity_token: token, oauth_return_to: request_path }
      assert_redirected_to "http://localhost#{request_path}"

      follow_redirect!
      assert_redirected_to new_user_session_url

      get new_user_session_path
      token = css_select("form[action='#{user_session_path}'] input[name=authenticity_token]").first["value"]
      post user_session_path, params: { authenticity_token: token, user: { email: other.email, password: "Password1!" } }
      assert_redirected_to "http://localhost#{request_path}"

      follow_redirect!
      assert_response :success
      assert_select "p", text: "Signed in as #{other.email}"
      assert_select "form[action=?][method=post] input[name=state][value=?]", oauth_authorization_path, "abc 123"
    end
  end

  test "a sign-out return value that isn't the authorization endpoint is ignored" do
    [
      "https://evil.example.com/oauth/authorize",
      "//evil.example.com/oauth/authorize",
      "///oauth/authorize",
      "////oauth/authorize",
      "http://localhost/oauth/authorize",
      "/people",
      "/oauth/authorize/native",
      "/oauth/authorized",
      "/oauth/authorize/../../people",
      "/oauth/authorize\n/people",
      "javascript:alert(1)",
      "",
      nil,
      { "path" => "/oauth/authorize" }
    ].each do |location|
      sign_in @user

      delete destroy_user_session_path, params: { oauth_return_to: location }

      assert_redirected_to root_url, "followed #{location.inspect}"
    end
  end

  test "signing out from elsewhere still goes home" do
    sign_in @user

    delete destroy_user_session_path

    assert_redirected_to root_url
  end

  private

  def authorize_path(redirect_uri, **extra)
    oauth_authorization_path(client_id: @application.uid, redirect_uri: redirect_uri, response_type: "code", scope: "user_read", **extra)
  end

  def authorize_path_stored_at(bytes, padding: :state)
    base = authorize_path("https://one.example.com/callback")

    case padding
    when :state
      path = "#{base}&state=#{"x" * (bytes - "#{base}&state=".to_json.bytesize)}"
    when :ampersands
      filler = "&k=v" * ((bytes - base.to_json.bytesize) / "&k=v".to_json.delete('"').bytesize)
      path = "#{base}#{filler}"
      path += "x" * (bytes - path.to_json.bytesize)
    end

    assert_equal bytes, path.to_json.bytesize
    path
  end

  def assert_session_cookie_fits
    Array(response.headers["Set-Cookie"]).flat_map { |header| header.split("\n") }.each do |cookie|
      assert_operator cookie.bytesize, :<, 4096
    end
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
