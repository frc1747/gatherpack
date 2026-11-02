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

  test "a redirect URI that isn't registered is refused" do
    sign_in @user
    get authorize_path("https://evil.example.com/callback")

    assert_select "input[name=redirect_uri]", count: 0
    assert_select "form[action=?]", oauth_authorization_path, count: 0
  end

  test "the different-account control signs out with a valid token and leads to sign-in" do
    with_forgery_protection do
      sign_in @user
      get authorize_path("https://one.example.com/callback")
      assert_response :success

      form = css_select("form[action='#{destroy_user_session_path}']").first
      assert_equal "false", form["data-turbo"]
      assert_equal "delete", form.at_css("input[name=_method]")["value"]
      assert_includes form.at_css("input[type=submit]")["value"], "Use a different account"
      token = form.at_css("input[name=authenticity_token]")["value"]

      delete destroy_user_session_path, params: { authenticity_token: token }
      assert_redirected_to root_path
      follow_redirect!
      assert_redirected_to new_user_session_path

      get authorize_path("https://one.example.com/callback")
      assert_redirected_to new_user_session_url
    end
  end

  private

  def authorize_path(redirect_uri)
    oauth_authorization_path(client_id: @application.uid, redirect_uri: redirect_uri, response_type: "code", scope: "user_read")
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
