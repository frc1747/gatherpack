require "test_helper"

class LocalSignupDisabledTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @original_local_signup = Settings[:local_signup].to_s
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(Rails.root.join("tmp", "local-signup-test-#{Process.pid}.pstore").to_s)
    Settings[:local_signup] = "false"
    Rails.application.reload_routes!
  end

  teardown do
    Settings[:local_signup] = @original_local_signup
    store_path = Settings.instance.store.path
    Settings.instance.store = @original_store
    File.delete(store_path) if File.exist?(store_path)
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
