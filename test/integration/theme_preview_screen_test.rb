require "test_helper"
require "support/modern_skin_test_settings"

# The theme preview's sample table scrolls on phones, like every table.
class ThemePreviewScreenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ModernSkinTestSettings

  setup do
    host! "localhost"
    user = User.create!(email: "admin@example.com", password: "Password1!")
    user.update_columns(admin: true)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    sign_in user
  end

  test "the sample table sits in a responsive wrapper" do
    with_setting(:feature_modern_skin, "true") do
      with_setting(:feature_theme_palette, "true") do
        get theme_preview_path

        assert_response :success
        assert_select ".table-responsive > table.table"
      end
    end
  end
end
