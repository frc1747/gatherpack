require "test_helper"
require "support/modern_skin_test_settings"

class PrintStyleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  setup do
    host! "localhost"
    user = User.create!(email: "print-viewer@example.com", password: "Password1!")
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    sign_in user
  end

  test "every page carries the saved print style" do
    with_setting(:print_css, "@page { margin: 1in; } .card { border: 0; }") do
      get root_path

      assert_response :success
      assert_select "head style[media=print]", count: 1
      assert_includes print_style, "@page { margin: 1in; } .card { border: 0; }"
    end
  end

  test "a blank print style leaves no style tag" do
    with_setting(:print_css, "") do
      get root_path

      assert_response :success
      assert_select "style[media=print]", false
    end
  end

  test "a closing style tag in the print style is escaped" do
    with_setting(:print_css, "a { color: red; }</style><script>alert(1)</script>") do
      get root_path

      assert_select "script", text: "alert(1)", count: 0
      assert_includes print_style, "a { color: red; }<\\/style><script>alert(1)<\\/script>"
    end
  end

  private

  def print_style
    response.body[%r{<style id="print-style" media="print">(.*?)</style>}m, 1]
  end
end
