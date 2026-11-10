require "test_helper"

class OauthApplicationsAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @app = OauthApplication.create!(name: "Team Wiki SSO", redirect_uri: "https://wiki.example.com/oauth/callback", scopes: "user_read user_email")
  end

  test "a member can't list OAuth applications" do
    sign_in create_user("member@example.com")

    get oauth_applications_path

    assert_not response.body.include?("Team Wiki SSO"), "a member lists the OAuth applications (status #{response.status})"
    assert_redirected_to root_path
  end

  test "an admin lists OAuth applications" do
    sign_in create_user("admin@example.com", admin: true)

    get oauth_applications_path

    assert_response :success
    assert_includes response.body, "Team Wiki SSO"
  end

  test "the client secret is shown once, right after creation" do
    sign_in create_user("admin@example.com", admin: true)

    post oauth_applications_path, params: { oauth_application: { name: "Chat", redirect_uri: "https://chat.example.com/callback", selected_scopes: [ "user_read" ] } }
    app = OauthApplication.find_by!(name: "Chat")
    follow_redirect!

    secret = css_select("[data-client-secret]").first&.text
    assert secret.present?, "the new client secret is not shown"
    assert app.secret_matches?(secret)

    get oauth_application_path(app)

    assert_empty css_select("[data-client-secret]")
  end

  test "an admin regenerates a client secret" do
    old_secret = @app.plaintext_secret
    sign_in create_user("admin@example.com", admin: true)

    post regenerate_secret_oauth_application_path(@app)
    follow_redirect!

    secret = css_select("[data-client-secret]").first&.text
    assert secret.present?, "the regenerated client secret is not shown"
    @app.reload
    assert @app.secret_matches?(secret)
    assert_not @app.secret_matches?(old_secret)
    assert_select "[data-controller=clipboard] [data-clipboard-target=source][data-client-secret]", text: secret
    assert_select "[data-clipboard-text-value]", count: 0

    get oauth_application_path(@app)

    assert_empty css_select("[data-client-secret]")
  end

  test "a member can't regenerate a client secret" do
    old_secret = @app.plaintext_secret
    sign_in create_user("member@example.com")

    post regenerate_secret_oauth_application_path(@app)

    assert_response :not_found
    assert @app.reload.secret_matches?(old_secret)
  end

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
