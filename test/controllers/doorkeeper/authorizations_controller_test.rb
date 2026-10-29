require "test_helper"

class Doorkeeper::AuthorizationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @user = User.create!(email: "oauth-member@example.com", password: "Password1!")
    Person.create!(user: @user, first_name: "Test", last_name: "Member")
    sign_in @user
  end

  test "the consent screen says what roles_read shares" do
    app = OauthApplication.create!(name: "Roster", redirect_uri: "https://client.example.com/callback", scopes: "user_read roles_read")

    get oauth_authorization_path, params: { client_id: app.uid, redirect_uri: app.redirect_uri, response_type: "code",
                                            scope: "user_read roles_read" }

    assert_response :success
    assert_includes response.body, "See whether you are an admin, architect or manager"
  end
end
