require "application_system_test_case"

class OauthAdminTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup do
    # config.hosts allows localhost but not Capybara's default 127.0.0.1.
    @original_app_host = Capybara.app_host
    @original_always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin

    visit new_oauth_application_path
    fill_in "Name", with: "Clipboard App"
    fill_in "oauth_application_redirect_uri", with: "https://example.com/callback"
    check "oauth_application_selected_scopes_user_read"
    click_on "Create"
    assert_text "This secret will not be shown again"
    @secret = secret_source.text
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_always_include_port
  end

  test "copy writes the secret to the clipboard and says so" do
    replace_clipboard "text => { window.copiedText = text; return Promise.resolve() }"

    copy_button.click

    assert_text "Copied"
    assert_equal @secret, evaluate_script("window.copiedText")
  end

  test "copy reaches the real clipboard when the browser allows it" do
    page.driver.browser.execute_cdp("Browser.grantPermissions",
      permissions: %w[clipboardReadWrite clipboardSanitizedWrite],
      origin: URI(current_url).then { |uri| "#{uri.scheme}://#{uri.host}:#{uri.port}" })

    copy_button.click

    assert_text "Copied"
    assert_equal @secret, evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")
  end

  test "when the browser refuses, the secret is selected and the page says so" do
    replace_clipboard "() => Promise.reject(new Error('denied'))"

    copy_button.click

    assert_text "Couldn't copy automatically"
    assert_equal @secret, evaluate_script("window.getSelection().toString()")
  end

  test "when the clipboard API doesn't exist, the secret is selected and the page says so" do
    execute_script "Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true })"

    copy_button.click

    assert_text "Couldn't copy automatically"
    assert_equal @secret, evaluate_script("window.getSelection().toString()")
  end

  test "index links leave the results frame instead of showing content missing" do
    visit oauth_applications_path
    click_on "Clipboard App"
    assert_text "Client ID"
    assert_no_text "Content missing"

    visit oauth_applications_path
    within("tr", text: "Clipboard App") { click_on "Edit" }
    assert_text "Editing Clipboard App"
    assert_no_text "Content missing"
  end

  test "index links still leave the frame after sorting, and delete works" do
    visit oauth_applications_path
    click_on "Last Updated"
    assert_text "Clipboard App"

    accept_confirm { within("tr", text: "Clipboard App") { click_on "Delete" } }

    assert_text "OAuth application was successfully destroyed."
    assert_no_text "Clipboard App"
  end

  test "browser Back doesn't bring the secret back" do
    click_on "Back to OAuth Applications"
    assert_text "OAuth Applications"
    assert_no_text @secret

    page.go_back

    assert_text "Clipboard App"
    assert_text "Client ID"
    assert_no_text @secret
    assert_no_text "This secret will not be shown again"
  end

  test "a request just under the limit survives the different-account control" do
    application = OauthApplication.find_by!(name: "Clipboard App")
    other = User.create!(email: "just-under-other@example.com", password: "Password1!")
    base = oauth_authorization_path(client_id: application.uid, redirect_uri: "https://example.com/callback", response_type: "code")
    request_path = "#{base}&state=#{"x" * (OauthAuthorizationReturn::MAX_STORED_BYTES - "#{base}&state=".to_json.bytesize)}"
    visit request_path
    assert_text "Signed in as"

    click_on "Use a different account"
    assert_current_path new_user_session_path
    fill_in "Email", with: other.email
    fill_in "Password", with: "Password1!"
    click_on "Sign in"

    assert_text "Signed in as #{other.email}"
    assert_equal "/oauth/authorize", URI(current_url).path
  end

  test "the secret appears once on the page" do
    assert_equal 1, page.text.scan(@secret).size
  end

  test "the consent page's different-account control signs out and returns to the request" do
    application = OauthApplication.find_by!(name: "Clipboard App")
    other = User.create!(email: "other-account@example.com", password: "Password1!")
    visit oauth_authorization_path(client_id: application.uid, redirect_uri: "https://example.com/callback", response_type: "code", state: "abc123")
    assert_text "Signed in as"
    assert_no_text other.email

    click_on "Use a different account"

    assert_current_path new_user_session_path
    fill_in "Email", with: other.email
    fill_in "Password", with: "Password1!"
    click_on "Sign in"

    assert_text "Signed in as #{other.email}"
    assert_equal "/oauth/authorize", URI(current_url).path
    assert_includes URI(current_url).query, "state=abc123"
    assert_includes URI(current_url).query, "client_id=#{application.uid}"
  end

  private

  def copy_button
    find("button[aria-label='Copy Client Secret']")
  end

  def secret_source
    copy_button.find(:xpath, "..").find("[data-clipboard-target=source]")
  end

  def replace_clipboard(write_text)
    execute_script "Object.defineProperty(navigator, 'clipboard', { value: { writeText: #{write_text} }, configurable: true })"
  end
end
