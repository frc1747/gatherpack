require "test_helper"
require "support/inventory_world"

class Inventory::ItemsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "a member sees the item page with stock by place, history and the buttons members may use" do
    with_inventory(@world) do
      stock!(@world, 14)
      sign_in @world.member.user
      get inventory_item_path(@world.screws)
      assert_response :success
      assert_select "#stock-by-place", text: /Shop › Cabinet › Bin 1/
      assert_select ".inventory-history", text: /Added 14 into Bin 1/
      assert_select ".inventory-bar a", text: "Used"
      assert_select ".inventory-bar a", text: "Count"
      assert_select ".inventory-bar a", text: "Move"
      assert_select "a", text: "Removed", count: 0
      assert_select "a", text: "Edit", count: 0
    end
  end

  test "a member gets Used, Count and Move when the item's home is a place they can't see" do
    with_inventory(@world) do
      closet = Location.create!(team: @world.outreach, name: "Outreach closet")
      @world.screws.update!(home_location: closet)
      stock!(@world, 5, location: closet)
      stock!(@world, 14)
      sign_in @world.member.user

      get inventory_item_path(@world.screws)
      assert_response :success
      assert_select "#stock-by-place", text: /Bin 1/
      assert_select "#stock-by-place", text: /Outreach closet/, count: 0
      assert_select ".inventory-bar a", text: "Used"
      assert_select ".inventory-bar a", text: "Count"
      assert_select ".inventory-bar a", text: "Move"
      assert_select ".inventory-bar a[href*=?]", @world.bin1.id, text: "Used"
    end
  end

  test "an inventory manager also gets the manager kinds and editing" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get inventory_item_path(@world.screws)
      assert_select "a", text: "Received"
      assert_select "a", text: "Removed"
      assert_select "a", text: "Edit"
    end
  end

  test "an outsider can't open the item" do
    with_inventory(@world) do
      sign_in @world.outsider.user
      get inventory_item_path(@world.screws)
      assert_response :not_found
    end
  end

  test "a member can't create or edit items" do
    with_inventory(@world) do
      sign_in @world.member.user
      assert_no_difference -> { Item.count } do
        post inventory_items_path, params: { item: { team_id: @world.club.id, name: "Nut" } }
      end
      patch inventory_item_path(@world.screws), params: { item: { name: "Renamed" } }
      assert_equal "M4 screw", @world.screws.reload.name
    end
  end

  test "an inventory manager adds an item with a home place" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get new_inventory_item_path
      assert_response :success
      post inventory_items_path, params: { item: { team_id: @world.robotics.id, name: "Zip tie", stock_unit_id: stock_unit("pack").id,
        home_location_id: @world.bin2.id, reorder_point: "5" } }
      item = Item.find_by!(name: "Zip tie")
      assert_redirected_to inventory_item_path(item)
      assert_equal @world.bin2, item.home_location
      assert_equal 5, item.reorder_point
      assert_equal "pack", item.unit
    end
  end

  test "a team manager can't put an item on a team outside their reach" do
    with_inventory(@world) do
      sign_in @world.manager.user
      assert_no_difference -> { Item.count } do
        post inventory_items_path, params: { item: { team_id: @world.art.id, name: "Paint" } }
      end
    end
  end

  test "the items list is scoped to what the person sees" do
    with_inventory(@world) do
      Item.create!(team: @world.art, name: "Paint brush")
      sign_in @world.member.user
      get inventory_items_path
      assert_response :success
      assert_select "#items", text: /M4 screw/
      assert_select "#items", text: /Paint brush/, count: 0
    end
  end

  test "a manager adds where to buy" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      post inventory_item_sources_path(@world.screws), params: { item_source: { vendor_name: "Parts Depot", vendor_part_number: "PD-1" } }
      assert_redirected_to inventory_item_path(@world.screws)
      assert_equal "Parts Depot", @world.screws.preferred_source.vendor_name
    end
  end

  test "a member can't add where to buy" do
    with_inventory(@world) do
      sign_in @world.member.user
      assert_no_difference -> { ItemSource.count } do
        post inventory_item_sources_path(@world.screws), params: { item_source: { vendor_name: "Parts Depot" } }
      end
    end
  end
end
