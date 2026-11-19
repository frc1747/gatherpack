require "application_system_test_case"

class PinnedFormButtonsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  PHONE = [ 390, 700 ].freeze
  DESKTOP = [ 1400, 700 ].freeze

  setup do
    # config.hosts allows localhost, not Capybara's default 127.0.0.1.
    @always_include_port = Capybara.always_include_port
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true

    @path = Rails.root.join("tmp", "pinned-form-buttons-system-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)

    @user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @user, first_name: "Ada", last_name: "Admin")
    sign_in @user
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
    Settings.instance.store = @original_store
    File.delete(@path) if File.exist?(@path)
    Capybara.app_host = nil
    Capybara.always_include_port = @always_include_port
  end

  [ [ "phone", PHONE ], [ "desktop", DESKTOP ] ].each do |name, size|
    test "the settings page's Save is in view at the top of the page at #{name} width" do
      Settings[:feature_pinned_form_buttons] = "true"
      page.driver.browser.manage.window.resize_to(*size)
      visit settings_path

      assert long_page?, "the settings page should run past the window"
      assert save_in_view?, "Save should be pinned to the bottom of the window"
    end

    test "the settings page's Save stays at the end of the form at #{name} width when the feature is off" do
      page.driver.browser.manage.window.resize_to(*size)
      visit settings_path

      assert long_page?, "the settings page should run past the window"
      assert_not save_in_view?, "Save should be at the end of the form, below the window"
    end
  end

  test "a short form's buttons stay where they are" do
    Settings[:feature_pinned_form_buttons] = "true"
    page.driver.browser.manage.window.resize_to(1400, 1400)
    visit new_badge_type_path

    # The row sits right under the fields it follows, with the window to spare.
    footer_top, footer_bottom, fields_bottom = evaluate_script(<<~JS)
      (() => {
        const footer = document.querySelector("main form .card-footer")
        const rect = footer.getBoundingClientRect()
        return [rect.top, rect.bottom, footer.previousElementSibling.getBoundingClientRect().bottom]
      })()
    JS
    assert_in_delta fields_bottom, footer_top, 1
    assert_operator footer_bottom, :<, evaluate_script("window.innerHeight")
  end

  private

  def long_page?
    evaluate_script("document.documentElement.scrollHeight > window.innerHeight + 200")
  end

  def save_in_view?
    evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector("main form input[type=submit][value=Save]").getBoundingClientRect()
        return window.scrollY === 0 && rect.top >= 0 && rect.bottom <= window.innerHeight
      })()
    JS
  end
end
