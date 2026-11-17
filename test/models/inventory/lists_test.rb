require "test_helper"
require "support/inventory_world"

# Place types, stock units, part conditions and reading types are managed
# lists (inventory spec §3.15): seeded with defaults, referenced by id, and
# their flags, not their names, drive what inventory does.
class Inventory::ListsTest < ActiveSupport::TestCase
  include InventoryWorld

  setup do
    @world = build_inventory_world
  end

  test "each list starts with its defaults, once" do
    assert_equal [ [ "Storage", true, false ], [ "Machine", false, true ] ],
      LocationType.ordered.pluck(:name, :holds_stock, :holds_installed_parts)
    assert_equal %w[each box pack roll foot set], StockUnit.ordered.pluck(:name)
    assert_equal [ "each" ], StockUnit.where(default: true).pluck(:name)
    assert_equal [ "New", "Good", "Worn", "Needs repair", "Broken", "Retired" ], UnitCondition.ordered.pluck(:name)
    assert_equal [ "Needs repair", "Broken" ], UnitCondition.attention.ordered.pluck(:name)
    assert_equal [ "Retired" ], UnitCondition.where(out_of_service: true).pluck(:name)
    assert_equal [ "Hours (h)", "Cycles", "Volts (V)" ], ReadingType.ordered.map(&:heading)

    assert_no_difference -> { LocationType.count + StockUnit.count + UnitCondition.count + ReadingType.count } do
      Inventory::Lists.seed_defaults!
    end
  end

  test "the four lists are registered under Orders and Inventory, shown while inventory is on" do
    %i[location_types stock_units unit_conditions reading_types].each do |key|
      list = GatherPack::ManagedLists.find(key)
      assert list, key
      assert_equal "Orders and Inventory", list.setup_section
      assert_equal :inventory, list.feature
    end
  end

  test "place types: a new place starts as Storage, and the flags, not the name, say what a place does" do
    assert_equal "storage", Location.new(team: @world.club, name: "Shelf").location_type.key
    assert @world.bin1.storage?
    assert_not @world.bin1.machine?
    assert @world.robot.machine?

    stand = LocationType.create!(name: "Test stand", holds_stock: false, holds_installed_parts: true)
    bench = Location.create!(team: @world.robotics, name: "Bench", location_type: stand)
    assert bench.takes_installs?
    assert_equal [ "Machine", "Test stand" ], LocationType.installable.map(&:name)
    assert_equal "a machine or a test stand", LocationType.installable_words
    motor = tracked_item!(@world, name: "Motor", units: 1).item_units.first
    with_inventory(@world) do
      motor.install!(into: bench, by: @world.admin)
      assert motor.reload.installed?
      error = assert_raises(Inventory::Refused) { record(@world, :added, 1, location: bench, reason: "Found") }
      assert_equal "Bench is a test stand, which holds no stock", error.message
    end
  end

  test "place types: renaming one shows everywhere it's used, and words follow the name" do
    location_type("machine").update!(name: "CNC mill", plural: "CNC mills")
    assert_equal "a CNC mill", @world.robot.reload.type_word(article: true)
    location_type("machine").update!(name: "Exhibit", plural: nil)
    assert_equal [ "an exhibit", "exhibits" ], [ @world.robot.reload.type_word(article: true), location_type("machine").word(count: :many) ]
    assert_equal [ "Exhibits" ], Inventory::Feature.new(key: :x, label: "X",
      nav_items: [ GatherPack::Feature::NavItem.new(label: "Machines", path: :inventory_machines_path, icon: "gears") ]).nav_items.map(&:label)
  end

  test "place types: a retired type leaves the picker and takes no parts, and its places keep it" do
    machine = location_type("machine")
    machine.retire!
    helper = Object.new.extend(ManagedListsHelper)
    assert_equal [ "Storage" ], helper.managed_list_choices(GatherPack::ManagedLists.find(:location_types)).map(&:first)
    assert_equal [ "Storage", "Machine (retired)" ],
      helper.managed_list_choices(GatherPack::ManagedLists.find(:location_types), machine.id).map(&:first)
    assert_equal machine, @world.robot.reload.location_type
    assert_not @world.robot.takes_installs?
    assert_not Location.new(team: @world.club, name: "New bot", location_type: machine).valid?
    motor = tracked_item!(@world, name: "Motor", units: 1).item_units.first
    with_inventory(@world) do
      error = assert_raises(Inventory::Refused) { motor.install!(into: @world.robot, by: @world.admin) }
      assert_equal "Machines are retired", error.message
    end
  end

  test "stock units: exactly one default; renaming shows on items; retiring hides it from pickers but keeps items" do
    pack = stock_unit("pack")
    pack.update!(default: true)
    assert_equal [ pack ], StockUnit.where(default: true).to_a
    assert_not pack.update(default: false)
    assert_not pack.update(active: false)

    @world.screws.update!(stock_unit: stock_unit("box"))
    stock_unit("box").update!(name: "carton", plural: "cartons")
    assert_equal "carton", @world.screws.reload.unit
    assert_equal [ "3 cartons", "1 carton" ], [ 3, 1 ].map { |count| @world.screws.stock_unit.quantity_text(count) }
    assert_equal "3", stock_unit("each").quantity_text(3)

    stock_unit("carton").retire!
    assert_not_includes StockUnit.active.pluck(:name), "carton"
    assert_equal "carton", @world.screws.reload.unit
    assert @world.screws.valid?
  end

  test "part conditions: renaming a default keeps the actions working, by key" do
    motor = tracked_item!(@world, name: "Motor", units: 1).item_units.first
    unit_condition("needs_repair").update!(name: "Out for repair")
    unit_condition("good").update!(name: "Fine")
    with_inventory(@world) do
      motor.mark_for_repair!(by: @world.admin, note: "Grinding")
      assert_equal "Out for repair", motor.reload.condition_label
      assert motor.flagged?
      motor.repaired!(by: @world.admin, note: "New bearing")
      assert_equal "Fine", motor.reload.condition_label
      motor.retire!(by: @world.admin, note: "Old")
      assert motor.reload.out_of_service?
      assert_equal "Retired", motor.condition_label
    end
  end

  test "part conditions: the flags drive spares, repair and retiring; a retired condition leaves the choices" do
    item = tracked_item!(@world, name: "Motor", units: 2)
    first, second = item.item_units.order(:code).to_a
    scratched = UnitCondition.create!(name: "Scratched", needs_attention: true)
    with_inventory(@world) do
      assert_equal 2, item.total_stock
      first.mark_for_repair!(by: @world.admin, note: "Deep scratch", condition: scratched.id)
      assert first.reload.flagged?
      assert_equal 1, item.total_stock
      assert_raises(Inventory::ConfirmNeeded) { first.install!(into: @world.robot, by: @world.admin) }

      scratched.retire!
      assert_not_includes UnitCondition.for_repair, scratched
      assert_equal scratched, first.reload.unit_condition
      error = assert_raises(Inventory::Refused) { second.mark_for_repair!(by: @world.admin, note: "x", condition: scratched.id) }
      assert_equal "Pick Needs repair or Broken", error.message
      assert_raises(Inventory::Refused) { second.check!(by: @world.admin, condition: "retired") }
    end
    assert_not UnitCondition.new(name: "Odd", needs_attention: true, out_of_service: true).valid?
  end

  test "part conditions: one in a unit's history can't be deleted, and merging repoints the history" do
    motor = tracked_item!(@world, name: "Motor", units: 1).item_units.first
    dented = UnitCondition.create!(name: "Dented")
    with_inventory(@world) { motor.check!(by: @world.admin, condition: dented.id) }
    with_inventory(@world) { motor.reload.check!(by: @world.admin, condition: "good") }
    assert_not dented.destroy
    assert_match(/history/, dented.errors.full_messages.to_sentence)

    # A merge loads the row afresh, as the merge screen does.
    UnitCondition.find(dented.id).merge_into!(unit_condition("worn"))
    assert_not UnitCondition.exists?(dented.id)
    assert_equal [ "Worn" ], motor.events.where(action: "check").order(:created_at).first(1).map { |event| event.condition_after.name }
  end

  test "reading types: renaming one renames it in saved readings; merging moves them; one with readings isn't deleted" do
    battery = tracked_item!(@world, name: "Battery", units: 1, readings: [ "Charge cycles", "Cycles" ])
    unit = battery.item_units.first
    charge = reading_type("Charge cycles")
    with_inventory(@world) { unit.check!(by: @world.admin, readings: { "Charge cycles" => "12" }) }
    charge.update!(name: "Charges")
    assert_equal [ "Charges", "Cycles" ], battery.reload.reading_types.map(&:name)
    assert_equal({ charge.id => 12 }, unit.reload.latest_readings)

    assert_not charge.destroy
    cycles = reading_type("Cycles")
    ReadingType.find(charge.id).merge_into!(cycles)
    assert_equal [ "Cycles" ], battery.reload.reading_types.map(&:name)
    assert_equal({ cycles.id => 12 }, unit.reload.latest_readings)

    cycles.retire!
    assert_equal [ "Cycles" ], battery.reload.reading_types.map(&:name)
    assert_not_includes ReadingType.active, cycles
  end

  test "place types: a type keeps stock or takes installed parts, not both" do
    both = LocationType.new(name: "Workbench", holds_stock: true, holds_installed_parts: true)
    assert_not both.valid?
    assert_includes both.errors.full_messages, "A type either keeps stock or has parts installed on it, not both"
    assert LocationType.new(name: "Building", holds_stock: false, holds_installed_parts: false).valid?
  end

  test "place types: a type in use can't drop a flag its places rely on" do
    storage = location_type("storage")
    with_inventory(@world) { stock!(@world, 5) }
    assert_not storage.update(holds_stock: false)
    assert_not storage.reload.update(holds_stock: false, holds_installed_parts: true)
    assert_equal [ "Counted stock is kept in storage places: move or remove it first" ], storage.errors.full_messages

    machine = location_type("machine")
    motor = tracked_item!(@world, name: "Motor", units: 1).item_units.first
    with_inventory(@world) { motor.install!(into: @world.robot, by: @world.admin) }
    assert_not machine.update(holds_installed_parts: false)
    assert_equal [ "Parts are installed on machines: take them off first" ], machine.errors.full_messages

    with_inventory(@world) { motor.reload.take_off!(by: @world.admin) }
    assert machine.reload.update(holds_installed_parts: false)
    with_inventory(@world) { record(@world, :used, 5) }
    assert storage.reload.update(holds_stock: false)
  end

  test "place types: merging is only into a type that does the same" do
    cart = LocationType.create!(name: "Cart")
    error = assert_raises(ActiveRecord::RecordInvalid) { location_type("machine").merge_into!(cart) }
    assert_match(/same way/, error.message)
    shelf = LocationType.create!(name: "Shelf")
    Location.create!(team: @world.club, name: "Top shelf", location_type: shelf)
    shelf.merge_into!(cart)
    assert_equal cart, Location.find_by!(name: "Top shelf").location_type
  end

  test "every default row has a key, so a list can't be emptied and defaults don't come back" do
    Inventory::Lists.defaults.each do |model, rows|
      assert rows.all? { |row| row[:key].present? } || model == StockUnit, model.name
    end
    hours = ReadingType.find_by!(key: "hours")
    assert_not hours.destroy
    assert ReadingType.exists?(hours.id)
    assert StockUnit.where(key: "each").exists?
  end

  test "shims for features written against the old columns and settings" do
    assert_equal "each", Inventory::Config.default_unit
    stock_unit("pack").update!(default: true)
    assert_equal "pack", Inventory::Config.default_unit

    item = Item.new(team: @world.club, name: "Gloves")
    item.unit = "Boxes"
    assert_equal "box", item.unit
    item.unit = "pair"
    item.save!
    assert_equal "pair", item.reload.unit
    assert StockUnit.exists?(name: "pair")
    item.unit = ""
    assert_equal "pair", item.unit
    assert_includes Location.storage, @world.bin1
    assert_not_includes Location.storage, @world.robot
  end
end
