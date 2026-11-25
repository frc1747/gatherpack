require "test_helper"
require "support/inventory_world"

class Inventory::SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "redirects home while the feature is off" do
    with_inventory(@world, feature_inventory: "false") do
      sign_in @world.member.user
      get inventory_root_path
      assert_redirected_to root_path
    end
  end

  test "a member finds an item by part number and sees where it is" do
    with_inventory(@world) do
      stock!(@world, 14)
      sign_in @world.member.user
      get inventory_root_path(q: "m4-12")
      assert_response :success
      assert_select "#inventory-results", text: /M4 screw/
      assert_select "#inventory-results li", text: "Shop › Cabinet › Bin 1: 14"
    end
  end

  test "shows Running low and Needs a count" do
    with_inventory(@world) do
      stock!(@world, 3)
      record(@world, :used, 5, location: @world.bin2)
      sign_in @world.member.user
      get inventory_root_path(q: "screw")
      assert_select ".badge", text: "Running low"
      assert_select ".badge", text: "Needs a count"
    end
  end

  test "someone outside the item's teams doesn't find it" do
    with_inventory(@world) do
      sign_in @world.outsider.user
      get inventory_root_path(q: "screw")
      assert_response :success
      assert_select "#inventory-results", count: 0
    end
  end

  test "someone outside inventory_users is turned away" do
    with_inventory(@world, inventory_users: @world.art.name) do
      sign_in @world.member.user
      get inventory_root_path
      assert_redirected_to root_path
    end
  end
end
