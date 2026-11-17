require "test_helper"
require "support/inventory_world"

class ItemTest < ActiveSupport::TestCase
  include InventoryWorld

  # Each test registers on a fresh registry; the app's comes back after.
  setup do
    @world = build_inventory_world
    @extensions = Inventory.extensions
    Inventory.instance_variable_set(:@extensions, Inventory::Extensions.new)
  end
  teardown { Inventory.instance_variable_set(:@extensions, @extensions) }

  test "an item without a reorder point is never low" do
    with_inventory(@world) do
      @world.screws.update!(reorder_point: nil)

      assert_not @world.screws.low?
      assert_not @world.screws.on_reorder_list?
      assert @world.screws.out_of_stock?
    end
  end

  test "low at or below the reorder point" do
    with_inventory(@world) do
      stock!(@world, 11)
      assert_not @world.screws.low?
      record(@world, :used, 1)
      assert @world.screws.low?
      assert @world.screws.on_reorder_list?
    end
  end

  test "what's on order from registered callables keeps an item off the list, summed" do
    with_inventory(@world) do
      stock!(@world, 4)
      assert @world.screws.on_reorder_list?
      assert_equal 0, @world.screws.on_order

      Inventory.extensions.register_on_order(->(items) { items.to_h { |item| [ item.id, 3 ] } })
      Inventory.extensions.register_on_order(->(items) { { items.first.id => 4 } })

      assert_equal 7, @world.screws.on_order
      assert @world.screws.low?, "low is stock alone"
      assert_not @world.screws.on_reorder_list?
    end
  end

  test "suggested quantity is the reorder quantity, or enough to get back to twice the reorder point" do
    with_inventory(@world) do
      stock!(@world, 4)
      assert_equal 16, @world.screws.suggested_quantity

      @world.screws.update!(reorder_quantity: 50)
      assert_equal 50, @world.screws.suggested_quantity
    end
  end

  test "the reorder list holds low items within the manager's reach, grouped by vendor with no source first" do
    with_inventory(@world) do
      stock!(@world, 3)
      nuts = Item.create!(team: @world.club, name: "Nut", reorder_point: 5)
      nuts.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "N-1", preferred: true)
      bolts = Item.create!(team: @world.club, name: "Bolt", reorder_point: 5)
      bolts.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "B-1")
      stock!(@world, 2, item: bolts)
      plenty = Item.create!(team: @world.club, name: "Washer", reorder_point: 5)
      stock!(@world, 50, item: plenty)
      Item.create!(team: @world.art, name: "Paint", reorder_point: 5)

      reorder = Inventory::Reorder.new(@world.keeper)
      assert_equal [ [ "No source yet", [ "M4 screw" ] ], [ "Parts Depot", [ "Nut", "Bolt" ] ] ],
        reorder.groups.map { |name, rows| [ name, rows.map { |row| row.item.name } ] }
      assert_equal "N-1", reorder.rows.find { |row| row.item == nuts }.source.vendor_part_number

      assert_not Inventory::Reorder.new(@world.member).allowed?
      assert_empty Inventory::Reorder.new(@world.member).rows
      assert_equal [ "Paint" ], Inventory::Reorder.new(@world.admin, team_id: @world.art.id).rows.map { |row| row.item.name }
      assert_equal [ "M4 screw" ], Inventory::Reorder.new(@world.keeper, category: "Fasteners").rows.map { |row| row.item.name }
    end
  end

  test "search finds active visible items by name, part numbers, category and source part number" do
    with_inventory(@world) do
      @world.screws.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "PD-9921")
      Item.create!(team: @world.club, name: "M4 screw (old)", active: false)
      Item.create!(team: @world.art, name: "M4 paint")

      [ "m4", "M4-12", "fasten", "pd-99" ].each do |query|
        assert_equal [ "M4 screw" ], Item.search(query, viewer: @world.member).map(&:name), query
      end
      assert_equal [ "M4 paint", "M4 screw" ], Item.search("m4", viewer: @world.admin).map(&:name)
      assert_empty Item.search("m4", viewer: @world.outsider).where(team: @world.club)
    end
  end

  test "line attributes describe the item and its preferred source" do
    @world.screws.update!(description: "Socket head", manufacturer: "Acme", stock_unit: stock_unit("pack"), url: "https://acme.example/m4")
    @world.screws.item_sources.create!(vendor_name: "Hardware Barn", vendor_part_number: "HB-1")
    @world.screws.item_sources.create!(vendor_name: "Parts Depot", vendor_part_number: "PD-1", url: "https://pd.example/1", preferred: true)

    assert_equal({ name: "M4 screw", description: "Socket head", manufacturer: "Acme", manufacturer_part_number: "M4-12",
      unit: "pack", vendor_name: "Parts Depot", vendor_part_number: "PD-1", url: "https://pd.example/1" },
      @world.screws.reload.line_attributes)
  end

  test "at most one preferred source" do
    first = @world.screws.item_sources.create!(vendor_name: "A", preferred: true)
    second = @world.screws.item_sources.create!(vendor_name: "B", preferred: true)

    assert_not first.reload.preferred?
    assert second.reload.preferred?
  end

  test "a new item takes the default stock unit" do
    assert_equal "each", Item.create!(team: @world.club, name: "Zip ties").unit
    stock_unit("pack").update!(default: true)
    assert_equal "pack", Item.create!(team: @world.club, name: "Cable ties").unit
    assert_equal [ "pack" ], StockUnit.where(default: true).pluck(:name)
  end

  test "an item tracks the reading types picked, in order, and unpicking keeps saved readings" do
    cycles = reading_type("Charge cycles")
    resistance = reading_type("name" => "Resistance", "unit" => "mΩ")
    item = Item.create!(team: @world.club, name: "Battery", reading_type_ids: [ resistance.id, "", cycles.id ])

    assert_equal [ "Resistance (mΩ)", "Charge cycles" ], item.reload.reading_types.map(&:heading)
    item.update!(reading_type_ids: [ cycles.id ])
    assert_equal [ cycles ], item.reload.reading_types
    assert ReadingType.exists?(resistance.id)
  end

  test "the home location can't be a machine" do
    @world.screws.home_location = @world.robot

    assert_not @world.screws.valid?
  end

  test "items with history can't be deleted" do
    with_inventory(@world) do
      stock!(@world, 1)

      assert_not @world.screws.destroy
      assert Item.exists?(@world.screws.id)
    end
  end
end
