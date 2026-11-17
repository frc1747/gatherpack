require "test_helper"
require "support/inventory_world"

class Inventory::ItemReadingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include InventoryWorld

  setup do
    host! "localhost"
    @world = build_inventory_world
    @battery = tracked_item!(@world, name: "Battery", readings: [ { "name" => "Charge cycles" } ])
  end

  def as(person, &block)
    with_inventory(@world) do
      sign_in person.user
      block.call
    end
  end

  test "a manager edits the readings a check asks for" do
    as(@world.keeper) do
      get edit_inventory_item_readings_path(@battery)
      assert_response :success
      assert_select "input[name='item[reading_fields][][name]'][value='Charge cycles']"

      patch inventory_item_readings_path(@battery), params: { item: { reading_fields: [
        { name: "Charge cycles", unit: "" }, { name: "Internal resistance", unit: "mΩ" }, { name: "", unit: "" }
      ] } }
      assert_redirected_to inventory_item_path(@battery)
      assert_equal [ { "name" => "Charge cycles" }, { "name" => "Internal resistance", "unit" => "mΩ" } ],
        @battery.reload.reading_fields
    end
  end

  test "a member can't edit readings" do
    as(@world.member) do
      get edit_inventory_item_readings_path(@battery)
      assert_redirected_to root_path
      patch inventory_item_readings_path(@battery), params: { item: { reading_fields: [ { name: "Hours" } ] } }
      assert_equal [ { "name" => "Charge cycles" } ], @battery.reload.reading_fields
    end
  end
end
