require "test_helper"

class SettingsRegisterTest < ActiveSupport::TestCase
  test "register adds a setting with its default" do
    Settings.register(:registered_test_setting, :string, "Registered Test", "hello", "Testing", "A registered setting")

    setting = Settings.get(:registered_test_setting)
    assert_equal "Registered Test", setting.name
    assert_equal "Testing", setting.group
    assert_equal "hello", Settings[:registered_test_setting]
    assert_includes Settings.settings("Testing"), setting
  end
end
