require "test_helper"
require "support/settings_test_helper"
Dir[Rails.root.join("db/migrate/2026111714*_create_*.rb")].each { |file| require file }

# The migrations that turn inventory's typed words and settings into managed
# lists. Each test puts the old column back inside its transaction (Postgres
# rolls the DDL back with it), writes rows the old way, and runs the
# migration's conversion.
class Inventory::ListConversionTest < ActiveSupport::TestCase
  include SettingsTestHelper

  setup do
    @connection = ActiveRecord::Base.connection
    team_type = TeamType.first || TeamType.create!(name: "Group")
    @team = Team.create!(name: "Conversion #{SecureRandom.hex(3)}", team_type: team_type)
  end

  # The old columns go with the rollback; forget them.
  teardown { [ Location, Item, ItemUnit, ItemUnitEvent ].each(&:reset_column_information) }

  # Runs the block with these raw values in the settings store, as the old
  # settings left them.
  def with_stored(values)
    with_settings({}) do
      store = Settings.instance.store
      store.transaction { values.each { |key, value| store[key] = value } }
      yield
    end
  end

  def insert(sql, *binds)
    @connection.select_value(ActiveRecord::Base.sanitize_sql_array([ "#{sql} RETURNING id", *binds ]))
  end

  def old_locations
    @connection.add_column :locations, :kind, :string, null: false, default: "storage"
    @connection.change_column_null :locations, :location_type_id, true
  end

  def place(name, kind)
    insert("INSERT INTO locations (id, team_id, name, kind, created_at, updated_at) VALUES (gen_random_uuid(), ?, ?, ?, now(), now())",
      @team.id, name, kind)
  end

  test "place types: the defaults, every place linked by kind, and a custom machine name renames Machine" do
    old_locations
    shop = place("Shop", "storage")
    rover = place("Rover", "machine")
    with_stored(inventory_machine_name: "Robot", inventory_machine_name_plural: "", inventory_machines: "on") do
      CreateLocationTypes.convert_up
    end

    assert_equal [ [ "Storage", "storage", true, false ], [ "Robot", "machine", false, true ] ],
      LocationType.ordered.pluck(:name, :key, :holds_stock, :holds_installed_parts)
    machine = LocationType.find_by!(key: "machine")
    assert_equal "Robots", machine.plural
    assert machine.active?
    assert_equal "storage", Location.find(shop).location_type.key
    assert_equal machine, Location.find(rover).location_type
    assert Location.find(rover).machine?
  end

  test "place types: machines turned off retire the Machine type, and its places keep it" do
    old_locations
    rover = place("Rover", "machine")
    with_stored(inventory_machine_name: "", inventory_machine_name_plural: "", inventory_machines: "Off") do
      CreateLocationTypes.convert_up
    end

    machine = LocationType.find_by!(key: "machine")
    assert_equal [ "Machine", "Machines", false ], [ machine.name, machine.plural, machine.active ]
    assert_equal machine, Location.find(rover).location_type
    assert_not Location.find(rover).takes_installs?
    assert_empty LocationType.installable
  end

  test "place types: rolling back gives the settings back" do
    old_locations
    with_stored(inventory_machine_name: "Exhibit", inventory_machine_name_plural: "Exhibit pieces", inventory_machines: "off") do
      CreateLocationTypes.convert_up
      CreateLocationTypes.convert_down
      values = Settings.instance.stored_values
      assert_equal [ "Exhibit", "Exhibit pieces", "off" ],
        values.values_at(:inventory_machine_name, :inventory_machine_name_plural, :inventory_machines)
    end
  end

  test "stock units: the defaults, each typed unit as a row (matched by name or plural), and the default setting" do
    @connection.add_column :items, :unit, :string, null: false, default: "each"
    @connection.change_column_null :items, :stock_unit_id, true
    item = ->(name, unit) { insert("INSERT INTO items (id, team_id, name, unit, created_at, updated_at) VALUES (gen_random_uuid(), ?, ?, ?, now(), now())", @team.id, name, unit) }
    screws = item.call("Screws", "each")
    wire = item.call("Wire", "Feet")
    tape = item.call("Tape", "spool")
    with_stored(inventory_default_unit: "spool") { CreateStockUnits.convert_up }

    assert_equal %w[each box pack roll foot set spool], StockUnit.ordered.pluck(:name)
    assert_equal [ "spool" ], StockUnit.where(default: true).pluck(:name)
    assert_equal "each", Item.find(screws).unit
    assert_equal "foot", Item.find(wire).unit
    assert_equal "spool", Item.find(tape).unit
  end

  test "stock units: with the default setting at each, each stays the default" do
    @connection.add_column :items, :unit, :string, null: false, default: "each"
    @connection.change_column_null :items, :stock_unit_id, true
    with_stored(inventory_default_unit: "each") { CreateStockUnits.convert_up }

    assert_equal [ "each" ], StockUnit.where(default: true).pluck(:key)
  end

  test "part conditions: the defaults with their flags, and units and their history linked by the old words" do
    @connection.add_column :item_units, :condition, :string, null: false, default: "new"
    @connection.add_column :item_unit_events, :condition_before, :string
    @connection.add_column :item_unit_events, :condition_after, :string
    @connection.change_column_null :item_units, :unit_condition_id, true
    @connection.change_column_null :items, :stock_unit_id, true
    shop = Location.create!(team: @team, name: "Shop", location_type: LocationType.create!(name: "Storage"))
    item = insert("INSERT INTO items (id, team_id, name, tracked, created_at, updated_at) VALUES (gen_random_uuid(), ?, 'Motor', true, now(), now())", @team.id)
    unit = insert("INSERT INTO item_units (id, item_id, location_id, condition, created_at, updated_at) VALUES (gen_random_uuid(), ?, ?, 'broken', now(), now())", item, shop.id)
    event = insert("INSERT INTO item_unit_events (id, item_unit_id, action, condition_before, condition_after, created_at) " \
      "VALUES (gen_random_uuid(), ?, 'mark_for_repair', 'good', 'broken', now())", unit)
    CreateUnitConditions.convert_up

    assert_equal [ [ "New", "new", false, false ], [ "Good", "good", false, false ], [ "Worn", "worn", false, false ],
      [ "Needs repair", "needs_repair", true, false ], [ "Broken", "broken", true, false ], [ "Retired", "retired", false, true ] ],
      UnitCondition.ordered.pluck(:name, :key, :needs_attention, :out_of_service)
    assert_equal "Broken", ItemUnit.find(unit).condition_label
    assert ItemUnit.find(unit).flagged?
    history = ItemUnitEvent.find(event)
    assert_equal [ "Good", "Broken" ], [ history.condition_before.name, history.condition_after.name ]
  end

  test "reading types: typed readings become rows, deduped by name and unit, and saved readings are keyed by id" do
    @connection.add_column :items, :reading_fields, :jsonb, null: false, default: []
    @connection.change_column_null :items, :stock_unit_id, true
    @connection.change_column_null :item_units, :unit_condition_id, true
    shop = Location.create!(team: @team, name: "Shop", location_type: LocationType.create!(name: "Storage"))
    fields = ->(list) { list.to_json }
    battery = insert("INSERT INTO items (id, team_id, name, tracked, reading_fields, created_at, updated_at) " \
      "VALUES (gen_random_uuid(), ?, 'Battery', true, ?::jsonb, now(), now())", @team.id,
      fields.call([ { name: "Hours", unit: "h" }, { name: "Charge cycles" }, { name: "Resistance", unit: "mΩ" } ]))
    motor = insert("INSERT INTO items (id, team_id, name, tracked, reading_fields, created_at, updated_at) " \
      "VALUES (gen_random_uuid(), ?, 'Motor', true, ?::jsonb, now(), now())", @team.id,
      fields.call([ { name: "hours", unit: "h" }, { name: "Hours", unit: "min" } ]))
    unit = insert("INSERT INTO item_units (id, item_id, location_id, created_at, updated_at) VALUES (gen_random_uuid(), ?, ?, now(), now())", battery, shop.id)
    event = insert("INSERT INTO item_unit_events (id, item_unit_id, action, readings, created_at) " \
      "VALUES (gen_random_uuid(), ?, 'check', ?::jsonb, now())", unit, { "Hours" => 12, "Old reading" => 3 }.to_json)
    CreateReadingTypes.convert_up

    assert_equal [ "Hours (h)", "Cycles", "Volts (V)" ], ReadingType.ordered.first(3).map(&:heading)
    assert_equal [ "Charge cycles", "Cycles", "Hours (h)", "Hours (min)", "Old reading", "Resistance (mΩ)", "Volts (V)" ],
      ReadingType.all.map(&:heading).sort
    assert_equal [ "Hours (h)", "Charge cycles", "Resistance (mΩ)" ], Item.find(battery).reading_types.map(&:heading)
    assert_equal [ "Hours (h)", "Hours (min)" ], Item.find(motor).reading_types.map(&:heading)
    hours = ReadingType.find_by!(name: "Hours")
    old = ReadingType.find_by!(name: "Old reading")
    assert_equal({ hours.id => 12, old.id => 3 }, ItemUnitEvent.find(event).readings)
  end
end
