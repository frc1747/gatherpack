require "test_helper"
require "support/inventory_world"

class Inventory::ItemTrackingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
  end

  def as(person, &block)
    with_inventory(@world) do
      sign_in person.user
      block.call
    end
  end

  test "an inventory manager turns tracking on, and the stock becomes units" do
    with_inventory(@world) { stock!(@world, 3) }
    as(@world.keeper) do
      post inventory_item_tracking_path(@world.screws)
      assert_redirected_to inventory_item_path(@world.screws)
      assert_equal "Each piece is now tracked: 3 units to label", flash[:notice]
      assert @world.screws.reload.tracked?
      assert_equal 3, @world.screws.item_units.count
    end
  end

  test "a member can't turn tracking on" do
    as(@world.member) do
      post inventory_item_tracking_path(@world.screws)
      assert_not @world.screws.reload.tracked?
    end
  end

  test "tracking can't be turned off while the item has units" do
    item = tracked_item!(@world, units: 1)
    as(@world.keeper) do
      delete inventory_item_tracking_path(item)
      assert item.reload.tracked?
    end
  end

  test "a manager turns tracking off for an item without units" do
    item = tracked_item!(@world, units: 0)
    as(@world.keeper) do
      delete inventory_item_tracking_path(item)
      assert_redirected_to inventory_item_path(item)
      assert_not item.reload.tracked?
    end
  end
end
