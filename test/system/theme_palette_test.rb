require "application_system_test_case"
require "support/modern_skin_test_settings"

class ThemePaletteSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  setup do
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    @admin = User.create!(email: "admin@example.com", password: "Password1!")
    @admin.update_columns(admin: true)
    Person.create!(user: @admin, first_name: "Ada", last_name: "Admin")

    @restores = [ override_setting(:feature_modern_skin, "true"), override_setting(:feature_theme_palette, "true") ]
    sign_in @admin
  end

  teardown do
    @restores.reverse_each(&:call)
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  test "changing a color updates both previews without saving" do
    visit edit_theme_path
    wait_for_token("light", "--gp-brand", "#6d6753")

    find("input[name='theme[brand_color]']").set("#34b233")

    wait_for_token("light", "--gp-brand", "#34b233")
    wait_for_token("dark", "--gp-on-brand", "#ffffff")
    assert_selector "[data-theme-palette-target=warnings] .alert", text: "White text is hard to read"
    assert_nil Theme.instance.brand_color
  end

  private

  def wait_for_token(mode, token, value)
    Timeout.timeout(Capybara.default_max_wait_time * 3) do
      sleep 0.1 until token_in_frame(mode, token) == value
    end
  end

  def token_in_frame(mode, token)
    within_frame(find("iframe[data-mode=#{mode}]")) do
      page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('#{token}').trim()")
    end
  rescue Selenium::WebDriver::Error::WebDriverError, Capybara::ElementNotFound
    nil
  end
end
