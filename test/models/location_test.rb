require "test_helper"
require "support/inventory_world"

class LocationTest < ActiveSupport::TestCase
  include InventoryWorld

  setup { @world = build_inventory_world }

  test "a new location takes its parent's team, and its full name is its path" do
    assert_equal @world.club, @world.bin1.team
    assert_equal "Shop › Cabinet › Bin 1", @world.bin1.full_name
    assert_equal @world.shop, @world.bin1.top_level
  end

  test "a code is unique within its top-level place" do
    clash = Location.new(parent: @world.cabinet, name: "Bin 3", code: "a-1")
    assert_not clash.valid?
    assert_includes clash.errors[:code].first, "already used in Shop"

    other_shop = Location.create!(team: @world.club, name: "Other shop")
    assert Location.new(parent: other_shop, name: "Bin 1", code: "A-1").valid?
  end

  test "a place with stock or units can't be made inactive" do
    with_inventory(@world) do
      stock!(@world, 2)

      assert_not @world.bin1.update(active: false)
      assert_includes @world.bin1.errors[:active].first, "move or remove it first"

      record(@world, :used, 2, location: @world.bin1.reload)
      assert @world.bin1.update(active: false)

      motor = tracked_item!(@world, units: 1)
      motor.item_units.first.update!(location: @world.bin2)
      assert_not @world.bin2.update(active: false)
    end
  end

  test "a place holding counted stock can't become a machine" do
    with_inventory(@world) do
      stock!(@world, 5)

      assert_not @world.bin1.update(kind: "machine")
      assert_includes @world.bin1.errors[:kind].first, "move or remove it first"

      record(@world, :used, 5, location: @world.bin1.reload)
      assert @world.bin1.update(kind: "machine")
    end
  end

  test "a place with history can't be deleted" do
    with_inventory(@world) do
      stock!(@world, 1)
      record(@world, :used, 1)

      assert_not @world.bin1.destroy
      assert Location.exists?(@world.bin1.id)
    end
  end

  test "a place can't be put inside itself" do
    @world.shop.parent = @world.bin1

    assert_not @world.shop.valid?
  end

  test "a machine is top level or under a storage place, not inside another machine" do
    cart = Location.create!(team: @world.robotics, name: "Robot cart")
    assert Location.new(parent: cart, name: "Practice robot", kind: "machine").valid?
    assert_not Location.new(parent: @world.robot, name: "Arm", kind: "machine").valid?
  end
end
