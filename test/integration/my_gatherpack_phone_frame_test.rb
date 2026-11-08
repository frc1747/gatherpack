require "test_helper"
require "my_gatherpack_test_helper"

class MyGatherpackPhoneFrameTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include MyGatherpackTestHelper

  setup do
    host! "localhost"
    @plugins = GatherPack::Features.instance_variable_get(:@plugins)
    @original_plugins = @plugins.dup
    @original_view_paths = ApplicationController.view_paths
    turn_on_my_gatherpack
    Settings[:feature_time_tracking] = "true"
    @member = create_login("Morgan")
  end

  teardown do
    restore_my_gatherpack
    ApplicationController.view_paths = @original_view_paths
    @plugins.replace(@original_plugins)
  end

  test "the header names the site and More opens the sidebar" do
    sign_in @member
    get root_path

    assert_select "header.navbar.d-md-none .navbar-brand", text: /Northwind Community/
    assert_select "header.navbar button[data-bs-target='#sidebarMenu']", count: 0
    assert_select "nav.phone-tabs.d-md-none button.phone-tab[data-bs-target='#sidebarMenu']", text: "More"
  end

  test "a member's tabs hold only the features that are on" do
    sign_in @member
    get root_path

    assert_equal [ "Home", "Hours", "More" ], tab_labels
    assert_select "nav.phone-tabs a.phone-tab.active", text: "Home"
  end

  test "Hours drops out with time tracking off" do
    Settings[:feature_time_tracking] = "false"
    sign_in @member
    get root_path

    assert_equal [ "Home", "More" ], tab_labels
  end

  test "a feature that is registered adds its tab, in order" do
    register_item "Forms", :forms_path, "Sign-ups", :signup_sheets_path
    NavHelper.define_method(:forms_path) { "/forms" }
    NavHelper.define_method(:signup_sheets_path) { "/signup_sheets" }
    MyGatherpack::Menu.table.merge!(forms_path: { top: 10 }, signup_sheets_path: { top: 20 })
    sign_in @member
    get root_path

    assert_equal [ "Home", "Forms", "Sign-ups", "Hours", "More" ], tab_labels
  ensure
    NavHelper.remove_method(:forms_path)
    NavHelper.remove_method(:signup_sheets_path)
    MyGatherpack::Menu.table.delete(:forms_path)
    MyGatherpack::Menu.table.delete(:signup_sheets_path)
  end

  test "a guardian gets Family first in place of Hours, once the family route exists" do
    register_item "Family", :family_path
    NavHelper.define_method(:family_path) { "/calendar" }
    MyGatherpack::Menu.table[:family_path] = { family: 10 }
    Person.define_method(:wards) { [ self ] }
    sign_in @member
    get root_path

    assert_equal [ "Family", "Home", "More" ], tab_labels
  ensure
    NavHelper.remove_method(:family_path)
    Person.remove_method(:wards)
    MyGatherpack::Menu.table.delete(:family_path)
  end

  test "a guardian sees no Family tab while the route is missing" do
    Person.define_method(:wards) { [ self ] }
    sign_in @member
    get root_path

    assert_equal [ "Home", "Hours", "More" ], tab_labels
  ensure
    Person.remove_method(:wards)
  end

  test "the bar is not on the kiosk or with the flag off" do
    get new_user_session_path
    assert_select "nav.phone-tabs", count: 0

    Settings[:feature_my_gatherpack] = "false"
    sign_in @member
    get root_path
    assert_select "nav.phone-tabs", count: 0
  end

  private

  def tab_labels
    css_select("nav.phone-tabs .phone-tab").map { |tab| tab.text.strip }
  end

  def register_item(*pairs)
    items = pairs.each_slice(2).map { |label, path| GatherPack::Feature::NavItem.new(label: label, path: path, icon: "flag") }
    GatherPack::Features.register(GatherPack::Feature.new(
      key: :"phone_test_#{items.first.label.parameterize}", label: "Phone Test", toggleable: false,
      nav_section: "Phone Test", nav_items: items
    ))
  end
end
