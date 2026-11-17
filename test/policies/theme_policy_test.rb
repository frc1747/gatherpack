require "test_helper"

class ThemePolicyTest < ActiveSupport::TestCase
  setup do
    @admin = User.create!(email: "theme-admin@example.com", password: "Password1!", admin: true)
    @member = User.create!(email: "theme-member@example.com", password: "Password1!")
    @theme = Theme.instance
  end

  test "only admins may update or edit the theme" do
    assert ThemePolicy.new(@admin, @theme).update?
    assert ThemePolicy.new(@admin, @theme).edit?
    assert_not ThemePolicy.new(@member, @theme).update?
    assert_not ThemePolicy.new(@member, @theme).edit?
  end
end
