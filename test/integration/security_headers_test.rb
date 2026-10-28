require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the sign-in page sends the security policies" do
    get new_user_session_path

    assert_response :success
    assert_security_policies
  end

  test "a signed-in profile page sends the security policies" do
    sign_in users(:one)

    get person_path(people(:one))

    assert_response :success
    assert_security_policies
  end

  test "the time kiosk sends the security policies" do
    sign_in users(:one)

    get time_kiosk_path

    assert_response :success
    assert_security_policies
  end

  test "each response gets a fresh nonce" do
    get new_user_session_path
    first = script_nonce
    get new_user_session_path

    assert_not_equal first, script_nonce
  end

  private

  def assert_security_policies
    assert_nil response.headers["Content-Security-Policy"], "The policy should only report for now"

    policy = response.headers["Content-Security-Policy-Report-Only"]
    assert policy.present?, "No Content-Security-Policy-Report-Only header"

    directives = policy.split(";").to_h { |directive| directive.strip.split(" ", 2) }
    assert_equal "'self'", directives["default-src"]
    assert_equal "'none'", directives["object-src"]
    assert_equal "'self'", directives["base-uri"]
    assert_equal "'self'", directives["frame-ancestors"]
    assert_includes directives["script-src"], "'nonce-#{script_nonce}'"
    assert_not_includes directives["script-src"], "'unsafe-inline'"

    assert_select "meta[name=csp-nonce][content=?]", script_nonce
    css_select("script").each do |script|
      assert_equal script_nonce, script["nonce"], "Script without the nonce: #{script.to_html.truncate(120)}"
    end

    assert_nil response.headers["Feature-Policy"], "The legacy Feature-Policy header should not be sent"
    permissions = response.headers["Permissions-Policy"]
    assert permissions.present?, "No Permissions-Policy header"
    assert_includes permissions, "camera=(self)"
    %w[microphone geolocation usb payment].each do |feature|
      assert_includes permissions, "#{feature}=()"
    end
  end

  def script_nonce
    policy = response.headers["Content-Security-Policy-Report-Only"].to_s
    policy[/'nonce-([^']+)'/, 1] || css_select("meta[name=csp-nonce]").first&.[]("content")
  end
end
