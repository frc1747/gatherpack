require "test_helper"
require "support/inventory_world"

class Inventory::LocationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  test "a member opens a place page and sees what's there with Used and Count" do
    with_inventory(@world) do
      stock!(@world, 14)
      sign_in @world.member.user
      get inventory_location_path(@world.bin1)
      assert_response :success
      assert_select "#place-items", text: /M4 screw/
      assert_select "#place-items a", text: "Used"
      assert_select "#place-items a", text: "Count"
      assert_select ".card-footer.screen-action-row a", text: "Count this place"
      assert_select "a", text: "Edit", count: 0
    end
  end

  test "a place with stock below zero shows Needs a count and Count now" do
    with_inventory(@world) do
      record(@world, :used, 2)
      sign_in @world.member.user
      get inventory_location_path(@world.bin1)
      assert_select ".badge", text: "Needs a count"
      assert_select "#place-items a", text: "Count now"
    end
  end

  test "Count this place saves the counts typed and skips blanks" do
    with_inventory(@world) do
      stock!(@world, 14)
      nuts = Item.create!(team: @world.club, name: "M4 nut", home_location: @world.bin1)
      stock!(@world, 5, item: nuts)
      sign_in @world.member.user
      get count_inventory_location_path(@world.bin1)
      assert_response :success
      assert_select "input[name=?]", "counts[#{@world.screws.id}]"

      post count_inventory_location_path(@world.bin1), params: { counts: { @world.screws.id => "12", nuts.id => "" } }
      assert_redirected_to inventory_location_path(@world.bin1)
      assert_equal "Saved 1 count (1 difference).", flash[:notice]
      assert_equal 12, @world.screws.stock_at(@world.bin1)
      assert_equal 5, nuts.stock_at(@world.bin1)
      assert_equal 14, StockMovement.counted.last.counted_quantity - StockMovement.counted.last.quantity
    end
  end

  test "Count this place is refused when members may not count" do
    with_inventory(@world, inventory_member_kinds: "used, moved") do
      stock!(@world, 14)
      sign_in @world.member.user
      get count_inventory_location_path(@world.bin1)
      assert_redirected_to inventory_location_path(@world.bin1)
      post count_inventory_location_path(@world.bin1), params: { counts: { @world.screws.id => "1" } }
      assert_equal 14, @world.screws.stock_at(@world.bin1)
    end
  end

  test "a manager builds a place inside another, which takes its team" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      get new_inventory_location_path(parent_id: @world.cabinet.id)
      assert_response :success
      post inventory_locations_path, params: { location: { parent_id: @world.cabinet.id, name: "Bin 3", code: "A-3", team_id: @world.art.id } }
      bin = Location.find_by!(name: "Bin 3")
      assert_redirected_to inventory_location_path(bin)
      assert_equal @world.club, bin.team
    end
  end

  test "a member can't add places" do
    with_inventory(@world) do
      sign_in @world.member.user
      assert_no_difference -> { Location.count } do
        post inventory_locations_path, params: { location: { parent_id: @world.cabinet.id, name: "Bin 3" } }
      end
    end
  end

  test "a duplicate code is refused within the top-level place" do
    with_inventory(@world) do
      sign_in @world.keeper.user
      post inventory_locations_path, params: { location: { parent_id: @world.cabinet.id, name: "Bin 9", code: "A-1" } }
      assert_response :unprocessable_entity
    end
  end

  test "the places tree lists visible places with label boxes for managers" do
    with_inventory(@world) do
      Location.create!(team: @world.art, name: "Studio")
      sign_in @world.keeper.user
      get inventory_locations_path
      assert_response :success
      assert_select ".inventory-tree", text: /Bin 1/
      assert_select ".inventory-tree", text: /Studio/, count: 0
      assert_select "input[name='places[]']"

      sign_in @world.member.user
      get inventory_locations_path
      assert_select "input[name='places[]']", count: 0
    end
  end
end
