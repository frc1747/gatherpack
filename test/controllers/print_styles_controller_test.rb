require "test_helper"
require "support/modern_skin_test_settings"

class PrintStylesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  setup do
    host! "localhost"
    @admin = create_user("print-admin@example.com", admin: true)
    @member = create_user("print-member@example.com")
  end

  test "an admin saves the print style" do
    with_setting(:print_css, "") do
      sign_in @admin
      patch print_style_path, params: { print_style: { css: "@page { margin: 1in; }" } }

      assert_redirected_to theme_path
      assert_equal "@page { margin: 1in; }", Settings[:print_css]
    end
  end

  test "an admin can save a blank print style" do
    with_setting(:print_css, "body { color: #000; }") do
      sign_in @admin
      patch print_style_path, params: { print_style: { css: "" } }

      assert_redirected_to theme_path
      assert_equal "", Settings[:print_css]
    end
  end

  test "a member can't save the print style" do
    with_setting(:print_css, "body { color: #000; }") do
      sign_in @member
      patch print_style_path, params: { print_style: { css: "body { display: none; }" } }

      assert_redirected_to root_path
      assert_equal "body { color: #000; }", Settings[:print_css]
    end
  end

  test "the theme edit page shows the saved print style" do
    with_setting(:print_css, "h1 { font-size: 20pt; }") do
      sign_in @admin
      get edit_theme_path

      assert_response :success
      assert_select "h2", text: "Print style"
      assert_select "textarea[name='print_style[css]'][rows='16']", text: "h1 { font-size: 20pt; }"
      assert_select "a[href=?]", edit_theme_path(print_style: "default", anchor: "print-style-form"), text: "Use the default"
    end
  end

  test "use the default fills the textarea with the bundled stylesheet" do
    with_setting(:print_css, "") do
      sign_in @admin
      get edit_theme_path(print_style: "default")

      bundled = Rails.root.join("app/assets/stylesheets/print_default.css").read
      assert_select "textarea[name='print_style[css]']" do |textarea|
        assert_equal bundled.strip, textarea.text.strip
      end
    end
  end

  test "the settings page names the default instead of printing the stylesheet" do
    skip "needs the settings pickers" unless Settings.respond_to?(:input)

    sign_in @admin
    get settings_path

    assert_response :success
    assert_select "textarea#settings_print_css.font-monospace"
    assert_includes response.body, "Default: The standard print style"
    assert_not_includes response.body, "Default: /*"
  end

  test "the setting defaults to the bundled stylesheet" do
    bundled = Rails.root.join("app/assets/stylesheets/print_default.css").read

    assert_equal bundled, Settings.get(:print_css).default_value
    assert_includes bundled, "@media print"
  end

  test "the default never hides card footers" do
    css = Rails.root.join("app/assets/stylesheets/print_default.css").read.gsub(%r{/\*.*?\*/}m, "")
    hiding = css.scan(/([^{}]+)\{([^{}]*)\}/).select do |selector, body|
      selector.include?(".card-footer") && body.match?(/display:\s*none/)
    end

    assert_empty hiding, "event Print pages put check-in notes in card footers"
  end

  private

  def create_user(email, admin: false)
    user = User.create!(email: email, password: "Password1!")
    user.update_columns(admin: admin)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
