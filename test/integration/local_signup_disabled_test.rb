require "test_helper"

class LocalSignupDisabledTest < ActionDispatch::IntegrationTest
  setup do
    @setting = Settings.get(:local_signup)
    @original_value = @setting.instance_variable_get(:@value)
    @setting.instance_variable_set(:@value, "false")
    Rails.application.reload_routes!
  end

  teardown do
    @setting.instance_variable_set(:@value, @original_value)
    Rails.application.reload_routes!
  end

  test "sign in page renders without a sign up link" do
    get new_user_session_path

    assert_response :success
    assert_select "a", text: "Sign Up", count: 0
  end

  test "forgot password page renders without a sign up link" do
    get new_user_password_path

    assert_response :success
    assert_select "a", text: "Sign Up", count: 0
  end
end
