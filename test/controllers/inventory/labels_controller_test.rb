require "test_helper"
require "support/inventory_world"

class Inventory::LabelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "a manager prints labels for a place and the places inside it, with QR codes" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_labels_path(places: [ @world.cabinet.id ], inside: 1, items: [ @world.screws.id ])
      assert_response :success
      assert_select ".inventory-label", count: 4
      assert_select ".inventory-label svg.inventory-qr", count: 4
      assert_select ".inventory-label-code", text: "A-1"
      assert_select ".inventory-label-path", text: "Shop › Cabinet › Bin 1"
    end
  end

  test "members can't print labels" do
    with_inventory(@world) do
      sign_in @world.member.user
      get inventory_labels_path(places: [ @world.bin1.id ])
      assert_redirected_to root_path
    end
  end
end
