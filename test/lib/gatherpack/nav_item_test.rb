require "test_helper"

class NavItemTest < ActiveSupport::TestCase
  NavItem = GatherPack::Feature::NavItem

  test "an item with no visible check is visible" do
    assert NavItem.new(label: "A", path: "/a", icon: "flag").visible?(nil)
  end

  test "a visible proc decides, and gets the user" do
    user = User.new
    assert NavItem.new(label: "A", path: "/a", icon: "flag", visible: ->(u) { u.equal?(user) }).visible?(user)
    assert_not NavItem.new(label: "A", path: "/a", icon: "flag", visible: ->(_) { false }).visible?(user)
  end
end
