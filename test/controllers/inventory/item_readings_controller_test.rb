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

  test "a manager picks the reading types a check asks for, from the list" do
    cycles = reading_type("Charge cycles")
    resistance = reading_type("name" => "Internal resistance", "unit" => "mΩ")
    old = reading_type("Old reading")
    old.retire!
    as(@world.keeper) do
      get edit_inventory_item_readings_path(@battery)
      assert_response :success
      assert_select "input[type=checkbox][name='item[reading_type_ids][]'][value=?][checked]", cycles.id
      assert_select "label", text: "Internal resistance (mΩ)"
      assert_select "label", text: /Old reading/, count: 0
      # Only admins manage the list itself.
      assert_select "a[href=?]", managed_list_path(:reading_types), count: 0

      patch inventory_item_readings_path(@battery), params: { item: { reading_type_ids: [ "", cycles.id, resistance.id, old.id ] } }
      assert_redirected_to inventory_item_path(@battery)
      assert_equal [ cycles, resistance ], @battery.reload.reading_types.to_a
    end
  end

  test "admins get a link to the reading types list" do
    as(@world.admin) do
      get edit_inventory_item_readings_path(@battery)
      assert_select "a[href=?]", managed_list_path(:reading_types), text: "Manage reading types"
    end
  end

  test "a retired reading type an item tracks stays ticked until unticked" do
    cycles = @battery.reading_types.first
    cycles.retire!
    as(@world.keeper) do
      get edit_inventory_item_readings_path(@battery)
      assert_select "label", text: "Charge cycles (retired)"
      patch inventory_item_readings_path(@battery), params: { item: { reading_type_ids: [ "", cycles.id ] } }
      assert_equal [ cycles ], @battery.reload.reading_types.to_a
      patch inventory_item_readings_path(@battery), params: { item: { reading_type_ids: [ "" ] } }
      assert_empty @battery.reload.reading_types
    end
  end

  test "a member can't edit readings" do
    as(@world.member) do
      get edit_inventory_item_readings_path(@battery)
      assert_redirected_to root_path
      patch inventory_item_readings_path(@battery), params: { item: { reading_type_ids: [ reading_type("Hours").id ] } }
      assert_equal [ "Charge cycles" ], @battery.reload.reading_types.map(&:name)
    end
  end
end
