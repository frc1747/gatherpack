require "test_helper"
require "support/inventory_world"

class Inventory::ImportTest < ActiveSupport::TestCase
  include InventoryWorld

  setup do
    @world = build_inventory_world
  end

  def import(csv, person: @world.keeper, team: @world.robotics)
    Inventory::Import.new(person: person, team_id: team.id, text: csv)
  end

  CSV_TEXT = <<~CSV
    Name,Category,Manufacturer,Manufacturer part number,Unit,Vendor,Vendor part number,Link,Place code,Quantity,Reorder point,Reorder quantity
    Zip tie,Consumables,Acme,ZT-100,pack,Parts Depot,PD-ZT,https://example.com/zt,A-2,6,2,10
    M4 screw (box),Fasteners,,M4-12,,Bolt Barn,BB-4,,a-1,40,,
    Heat shrink,Electrical,,,,,,,Z-9,5,,
  CSV

  test "the preview shows what's created, updated, and rows with an unknown place code" do
    with_inventory(@world) do
      preview = import(CSV_TEXT)
      assert preview.valid?
      assert_equal %i[create update skip], preview.rows.map(&:action)
      assert_equal @world.screws, preview.rows.second.item
      assert_equal @world.bin1, preview.rows.second.location
      assert_equal [ "Unknown place code Z-9" ], preview.rows.third.problems
      assert_no_difference -> { Item.count } do
        preview.rows
      end
    end
  end

  test "apply creates, updates by part number and records added movements" do
    with_inventory(@world) do
      result = nil
      assert_difference -> { Item.count }, 1 do
        result = import(CSV_TEXT).apply!
      end
      assert_equal 1, result.created
      assert_equal 1, result.updated
      assert_equal [ "row 4" ], result.skipped

      zip = Item.find_by!(name: "Zip tie")
      assert_equal [ @world.robotics, "pack", 2, 10, @world.bin2 ], [ zip.team, zip.unit, zip.reorder_point, zip.reorder_quantity, zip.home_location ]
      assert_equal [ "Parts Depot", "PD-ZT", "https://example.com/zt", true ],
        zip.item_sources.first.then { |source| [ source.vendor_name, source.vendor_part_number, source.url, source.preferred ] }
      assert_equal 6, zip.stock_at(@world.bin2)

      movement = zip.stock_movements.sole
      assert_equal [ "added", "Imported", @world.keeper ], [ movement.kind, movement.reason, movement.person ]

      @world.screws.reload
      assert_equal "M4 screw", @world.screws.name
      assert_equal 40, @world.screws.stock_at(@world.bin1)
      assert_equal "Bolt Barn", @world.screws.preferred_source.vendor_name
      assert_not Item.exists?(name: "Heat shrink")
    end
  end

  test "a row without a part number matches by name" do
    with_inventory(@world) do
      Item.create!(team: @world.club, name: "Heat shrink")
      preview = import("Name,Category\nheat shrink,Electrical\n")
      assert_equal :update, preview.rows.sole.action
      assert_no_difference -> { Item.count } do
        preview.apply!
      end
      assert_equal "Electrical", Item.find_by!(name: "Heat shrink").category
    end
  end

  test "bad numbers and a missing Name column are reported" do
    with_inventory(@world) do
      assert_equal [ "Quantity must be a whole number" ], import("Name,Place code,Quantity\nNut,A-1,2.5\n").rows.sole.problems
      missing = import("Category\nFasteners\n")
      assert_not missing.valid?
      assert_includes missing.errors.full_messages, "The first line needs a Name column"
    end
  end

  test "only for a team the person manages" do
    with_inventory(@world) do
      assert_not import(CSV_TEXT, team: @world.art).valid?
      assert_not import(CSV_TEXT, person: @world.member).valid?
      assert_raises(Inventory::Refused) { import(CSV_TEXT, person: @world.member).apply! }
    end
  end
end
