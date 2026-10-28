require "test_helper"

class OauthApplicationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    OauthApplication.create!(name: "Team Wiki SSO", redirect_uri: "https://wiki.example.com/oauth/callback", scopes: "user_read user_email")
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

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
