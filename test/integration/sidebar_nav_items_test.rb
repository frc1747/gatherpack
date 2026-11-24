require "test_helper"

class SidebarNavItemsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @plugins = GatherPack::Features.instance_variable_get(:@plugins)
    @original_plugins = @plugins.dup
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  teardown do
    @plugins.replace(@original_plugins)
  end

  test "hides items whose visible check is false and keeps the rest" do
    register_section "Nav Test A", [
      nav_item("Shown Plain"),
      nav_item("Shown Checked", visible: ->(_) { true }),
      nav_item("Hidden Item", visible: ->(_) { false })
    ]

    get root_path

    assert_select ".sidebar a", text: /Shown Plain/
    assert_select ".sidebar a", text: /Shown Checked/
    assert_select ".sidebar a", text: /Hidden Item/, count: 0
    assert_select ".sidebar h6", text: "Nav Test A"
  end

  test "a section with no visible items loses its heading" do
    register_section "Nav Test B", [ nav_item("Hidden Item", visible: ->(_) { false }) ]

    get root_path

    assert_select ".sidebar h6", text: "Nav Test B", count: 0
  end

  private

  def nav_item(label, **options)
    GatherPack::Feature::NavItem.new(label: label, path: "/calendar", icon: "flag", **options)
  end

  def register_section(name, items)
    GatherPack::Features.register(GatherPack::Feature.new(
      key: :"nav_test_#{name.parameterize}", label: name, toggleable: false,
      nav_section: name, nav_items: items
    ))
  end
end
