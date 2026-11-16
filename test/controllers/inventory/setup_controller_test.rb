require "test_helper"
require "support/inventory_world"

class Inventory::SetupControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "an admin sees the three settings with their current values" do
    with_inventory(@world, inventory_users: "Alpha\nBeta", inventory_reorder_notice: "each") do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_response :success
      assert_select "h1", text: "Inventory setup"
      assert_includes response.body, "Who Can Use Inventory"
      assert_includes response.body, "Inventory Managers"
      assert_includes response.body, "Running Low Notices"
      assert_not_includes response.body, "Undo Minutes"
      assert_includes response.body, "An email each time"
    end
  end

  test "saving keeps the text as it was" do
    original = { inventory_users: "Alpha\r\nBeta", inventory_managers: "Keeper > Club", inventory_reorder_notice: "daily" }
    with_inventory(@world, **original) do
      sign_in @world.admin.user
      get inventory_setup_path
      assert_response :success
      form = css_select("form[action='#{update_settings_path}'], form[action='#{inventory_setup_path}']").first
      assert form
      if Settings.respond_to?(:input)
        # What the pickers post for the saved values (SettingInput).
        patch update_settings_path, params: { return_to: inventory_setup_path, settings: {
          inventory_users: { values: [ "", "Alpha", "Beta" ] },
          inventory_managers: { rows: { "0" => { line: "Keeper > Club" } } },
          inventory_reorder_notice: "daily"
        } }
        assert_redirected_to inventory_setup_path
      else
        patch inventory_setup_path, params: { settings: original }
      end
      assert_response :see_other unless Settings.respond_to?(:input)
      original.each { |key, text| assert_equal text, Settings[key] }
      assert_equal Inventory::Config::DEFAULT_UNDO_MINUTES.to_s, Settings[:inventory_undo_minutes]
    end
  end

  test "update saves the three settings and leaves the others" do
    with_inventory(@world) do
      sign_in @world.admin.user
      patch inventory_setup_path, params: { settings: { inventory_reorder_notice: "off", inventory_users: "Club", inventory_undo_minutes: "99" } }
      assert_redirected_to inventory_setup_path
      assert_equal "off", Settings[:inventory_reorder_notice]
      assert_equal "Club", Settings[:inventory_users]
      assert_not_equal "99", Settings[:inventory_undo_minutes]
    end
  end

  test "only admins open or save the page" do
    with_inventory(@world) do
      [ @world.manager, @world.keeper, @world.member ].each do |person|
        sign_in person.user
        get inventory_setup_path
        assert_redirected_to root_path
        patch inventory_setup_path, params: { settings: { inventory_users: "Nobody" } }
        assert_redirected_to root_path
        assert_not_equal "Nobody", Settings[:inventory_users]
        sign_out person.user
      end
    end
  end

  test "the Inventory page links to Setup for admins only" do
    with_inventory(@world) do
      sign_in @world.admin.user
      get inventory_root_path
      assert_select "a[href=?]", inventory_setup_path
      sign_out @world.admin.user
      sign_in @world.keeper.user
      get inventory_root_path
      assert_select "a[href=?]", inventory_setup_path, count: 0
    end
  end

  test "the menu entry is for admins" do
    skip "menu entries can't be hidden per person here" unless GatherPack::Feature::NavItem.members.include?(:visible)
    item = GatherPack::Features.find(:inventory).nav_items.find { |nav| nav.label == "Setup" }
    assert_equal "gear", item.icon
    assert item.visible.call(@world.admin.user)
    assert_not item.visible.call(@world.keeper.user)
  end

  test "the settings page points to Setup when pickers are there" do
    skip "needs the settings seam" unless Settings.respond_to?(:page)
    with_inventory(@world) do
      sign_in @world.admin.user
      get settings_path
      assert_select "a[href=?]", inventory_setup_path
    end
  end
end
