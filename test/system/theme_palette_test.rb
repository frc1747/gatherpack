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

  test "the swatch works while a color is Automatic, and picking turns Automatic off" do
    visit edit_theme_path

    assert_no_selector "input[type=color][disabled]"
    assert_checked_field "brand_color_automatic"

    page.execute_script(<<~JS)
      const swatch = document.querySelector("[data-field=brand_color] [data-picker]")
      swatch.value = "#34b233"
      swatch.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    assert_field "theme[brand_color]", with: "#34b233"
    assert_unchecked_field "brand_color_automatic"
    wait_for_token("light", "--gp-brand", "#34b233")
  end

  test "installed app colors have a swatch and a hex box that stay in step" do
    visit edit_theme_path

    assert_selector ".fancy-color-container input[type=color][name='theme[pwa_theme_color]']"
    find(".fancy-color-container input[type=text][name='theme[pwa_theme_color]']").set("#123456")

    assert_equal "#123456", find(".fancy-color-container input[type=color][name='theme[pwa_theme_color]']").value
  end

  test "on a split palette, secondary buttons on the page hover with the cards' text" do
    visit theme_preview_path(mode: "light", background_color: "#505050", surface_color: "#c8c8c8")

    hover = page.evaluate_script(
      "getComputedStyle(document.querySelector('main > p .btn-outline-secondary')).getPropertyValue('--bs-btn-hover-color').trim()"
    )
    ink = ThemePalette::Generator.new(ThemePalette::Picks.new(background_color: "#505050", surface_color: "#c8c8c8"))
      .palette(:light).surface_tokens.fetch("--gp-text")
    assert_equal ink, hover
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
