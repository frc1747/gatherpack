require "test_helper"

class SessionRevocationTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password1!"

  setup do
    host! "localhost"
    @admin = User.create!(email: "admin@example.com", password: PASSWORD, admin: true)
    @person = Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")
  end

  test "a copied session cookie stops working after sign-out" do
    sign_in_with_password
    get people_path
    assert_response :success, "precondition: signed in"

    key = Rails.application.config.session_options[:key]
    stolen = cookies[key]
    assert stolen.present?, "precondition: session cookie #{key} present"

    delete destroy_user_session_path
    get people_path
    assert_response :redirect, "precondition: signed out"

    cookies[key] = stolen
    get people_path

    refute_equal 200, response.status, "a session cookie copied before sign-out still reaches /people as the admin"
    assert_redirected_to new_user_session_path
  end

  test "signing out ends the login's sessions on other devices" do
    other_device = open_session
    other_device.host! "localhost"
    other_device.post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }

    sign_in_with_password
    delete destroy_user_session_path

    other_device.get people_path
    other_device.assert_redirected_to new_user_session_path
  end

  test "a copied remember-me cookie stops working after sign-out" do
    sign_in_with_password(remember_me: "1")
    stolen = cookies["remember_user_token"]
    assert stolen.present?, "precondition: remember-me cookie present"

    delete destroy_user_session_path
    sign_in_with_password(remember_me: "1")

    thief = open_session
    thief.host! "localhost"
    thief.cookies["remember_user_token"] = stolen
    thief.get people_path

    thief.assert_redirected_to new_user_session_path
  end

  test "a session ends after timeout_in without a request" do
    sign_in_with_password

    travel Devise.timeout_in - 1.minute do
      get people_path
      assert_response :success
    end

    travel Devise.timeout_in * 2 do
      get people_path
      assert_equal "Your session expired. Please sign in again to continue.", flash[:alert]
      follow_redirect!
      assert_redirected_to new_user_session_path
    end
  end

  test "a valid remember-me cookie keeps the session from timing out" do
    sign_in_with_password(remember_me: "1")

    travel Devise.timeout_in + 1.minute do
      get people_path
      assert_response :success
    end
  end

  test "changing the password ends the login's other sessions but not the one that changed it" do
    other_device = open_session
    other_device.host! "localhost"
    other_device.post user_session_path, params: { user: { email: @admin.email, password: PASSWORD } }
    other_device.get people_path
    other_device.assert_response :success

    sign_in_with_password
    patch person_user_path(@person), params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!", old_password: PASSWORD } }
    assert_redirected_to person_path(@person)

    other_device.get people_path
    other_device.assert_redirected_to new_user_session_path
    get people_path
    assert_response :success
  end

  test "changing the password revokes the login's API tokens and grants" do
    application = Doorkeeper::Application.create!(name: "App", redirect_uri: "https://example.com/callback", scopes: "user_read")
    token = Doorkeeper::AccessToken.create!(resource_owner_id: @admin.id, application_id: application.id, scopes: "user_read", expires_in: 1.hour)
    grant = Doorkeeper::AccessGrant.create!(resource_owner_id: @admin.id, application_id: application.id, scopes: "user_read",
      expires_in: 10.minutes, redirect_uri: "https://example.com/callback")

    @admin.update!(password: "NewPass123!", password_confirmation: "NewPass123!")

    assert token.reload.revoked?, "an API token issued before the password change still works"
    assert grant.reload.revoked?
  end

  private

  def sign_in_with_password(remember_me: "0")
    post user_session_path, params: { user: { email: @admin.email, password: PASSWORD, remember_me: remember_me } }
    assert_redirected_to root_path
  end
end
