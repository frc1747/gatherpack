require "test_helper"

class QuietRootSigninTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { host! "localhost" }

  test "signed out home page redirects to sign in without a message" do
    get root_path
    assert_redirected_to new_user_session_path
    assert_nil flash[:notice]
    assert_nil flash[:alert]
    follow_redirect!
    assert_response :success
    assert_no_match(/must be logged in/, response.body)
  end

  test "home page resets the return path" do
    get people_path
    get root_path
    assert_equal root_path, session[:user_return_to]
  end

  test "signed out protected page still shows the message" do
    get people_path
    assert_redirected_to new_user_session_path
    assert_equal "You must be logged in to do that", flash[:notice]
  end

  test "signed out setup page still requires login" do
    get setup_path
    assert_redirected_to new_user_session_path
    assert_equal "You must be logged in to do that", flash[:notice]
  end

  test "signing out shows the signed out message on the sign in page" do
    user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Mia", last_name: "Member")
    sign_in user
    delete destroy_user_session_path
    assert_redirected_to root_path
    follow_redirect!
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_response :success
    assert_match(/Signed out successfully\./, response.body)
  end

  test "resetting a password shows the password changed message" do
    user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Mia", last_name: "Member")
    token = user.send_reset_password_instructions
    put user_password_path, params: { user: { reset_password_token: token, password: "NewPassword1!", password_confirmation: "NewPassword1!" } }
    assert_response :redirect
    follow_redirect!
    follow_redirect! while response.redirect?
    assert_match(/Your password has been changed successfully/, response.body)
  end

  test "signed in home page renders the dashboard" do
    user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Mia", last_name: "Member")
    sign_in user
    get root_path
    assert_response :success
  end
end
