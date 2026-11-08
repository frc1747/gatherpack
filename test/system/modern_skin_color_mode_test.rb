require "application_system_test_case"
require "support/modern_skin_test_settings"

class ModernSkinColorModeTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  setup do
    # config.hosts allows localhost, not Capybara's default 127.0.0.1.
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    @user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: @user, first_name: "Jo", last_name: "Example")

    @restore_setting = override_setting(:feature_modern_skin, "true")

    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: "light" } ])
  end

  teardown do
    @restore_setting.call
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  test "signing out doesn't leave the next person with the last person's dark mode" do
    sign_in @user
    visit root_path
    assert_color_mode "light"

    find("[data-color-mode-mode-param=dark]").click
    assert_color_mode "dark"
    assert_saved "dark"

    click_on "Sign Out"
    assert_current_path new_user_session_path
    assert_color_mode "light"
  end

  test "going back to the kiosk from a dark page is light" do
    @user.update_columns(color_mode: "dark", admin: true)
    sign_in @user

    visit time_kiosk_path
    assert_color_mode "light"

    find("a.navbar-brand").click
    assert_current_path root_path
    assert_color_mode "dark"

    page.go_back
    assert_current_path time_kiosk_path
    assert_color_mode "light"
  end

  test "a choice survives going back to the page it was made on" do
    sign_in @user
    visit root_path
    assert_color_mode "light"

    find("[data-color-mode-mode-param=dark]").click
    assert_color_mode "dark"
    assert_saved "dark"

    click_on "People"
    assert_current_path people_path
    page.go_back
    assert_current_path root_path
    assert_color_mode "dark"
    assert_selector "[data-color-mode-mode-param=dark][aria-pressed=true]"
  end

  private

  def assert_color_mode(mode)
    assert_selector "html[data-bs-theme=#{mode}]", visible: :all
  end

  def assert_saved(mode)
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until @user.reload.color_mode == mode
    end
  end
end
