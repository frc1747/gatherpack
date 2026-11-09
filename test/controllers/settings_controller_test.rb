require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  MARKER = "GOCSPX-settings-page-marker".freeze

  setup do
    host! "localhost"
    @store_path = Rails.root.join("tmp", "settings-test-#{Process.pid}-#{SecureRandom.hex(4)}.pstore").to_s
    @original_store = Settings.instance.store
    @original_value = Settings.get(:google_oauth_client_secret).instance_variable_get(:@value)
    Settings.instance.store = PStore.new(@store_path)

    user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: user, first_name: "Test", last_name: "Admin")
    sign_in user
  end

  teardown do
    Settings.get(:google_oauth_client_secret).instance_variable_set(:@value, @original_value)
    Settings.instance.store = @original_store
    FileUtils.rm_f(@store_path)
  end

  test "the settings page does not echo OAuth client secrets back into the HTML" do
    Settings[:google_oauth_client_secret] = MARKER

    get settings_path

    assert_response :success
    assert_not_includes response.body, MARKER, "GET /settings renders the OAuth client secret into the page"
    assert_includes response.body, "Set (leave blank to keep it)"
  end

  test "saving the settings page with a blank secret keeps it, and a new one replaces it" do
    Settings[:google_oauth_client_secret] = MARKER

    post update_settings_path, params: { settings: { google_oauth_client_secret: "" } }
    assert_equal MARKER, Settings[:google_oauth_client_secret]

    post update_settings_path, params: { settings: { google_oauth_client_secret: "GOCSPX-new" } }
    assert_equal "GOCSPX-new", Settings[:google_oauth_client_secret]
  end
end
