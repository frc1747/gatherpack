# Place types (inventory spec §3.15): a managed list that replaces
# locations.kind. A type's flags say what its places do: hold counted stock,
# or have tracked parts installed on them. The inventory_machines,
# inventory_machine_name and inventory_machine_name_plural settings become
# the Machine row: a custom name renames it, "off" retires it. The settings
# are left in the store, so rolling back gets them back as they were.
class CreateLocationTypes < ActiveRecord::Migration[8.1]
  class LocationType < ActiveRecord::Base
    self.table_name = "location_types"
  end

  DEFAULTS = [
    { name: "Storage", plural: "Storage places", key: "storage", holds_stock: true, holds_installed_parts: false },
    { name: "Machine", plural: "Machines", key: "machine", holds_stock: false, holds_installed_parts: true }
  ].freeze

  def change
    create_table :location_types, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :holds_stock, null: false, default: true
      t.boolean :holds_installed_parts, null: false, default: false
      t.timestamps
    end
    add_index :location_types, "lower(name)", unique: true
    add_index :location_types, :key, unique: true
    add_reference :locations, :location_type, type: :uuid, foreign_key: true

    reversible do |dir|
      dir.up { self.class.convert_up }
      dir.down { self.class.convert_down }
    end

    change_column_null :locations, :location_type_id, false
    remove_column :locations, :kind, :string, null: false, default: "storage"
  end

  # Seeds the defaults, takes the machine settings into the Machine row and
  # points every place at the row for its kind.
  def self.convert_up
    LocationType.reset_column_information
    seed_defaults
    machine = LocationType.find_by!(key: "machine")
    name = stored_setting(:inventory_machine_name).to_s.strip
    plural = stored_setting(:inventory_machine_name_plural).to_s.strip
    attributes = {}
    attributes[:name] = name if name.present?
    attributes[:plural] = plural.presence || (name.pluralize if name.present?)
    attributes[:active] = false if stored_setting(:inventory_machines).to_s.strip.casecmp?("off")
    machine.update!(attributes.compact)

    # Any kind the enum didn't know still gets a row of its own.
    kinds = connection.select_values("SELECT DISTINCT kind FROM locations WHERE kind IS NOT NULL")
    kinds.each do |kind|
      type = LocationType.find_by(key: kind) || find_or_create_by_name(kind.humanize)
      connection.execute(sanitize([ "UPDATE locations SET location_type_id = ? WHERE kind = ?", type.id, kind ]))
    end
    storage = LocationType.find_by!(key: "storage")
    connection.execute(sanitize([ "UPDATE locations SET location_type_id = ? WHERE location_type_id IS NULL", storage.id ]))
  end

  # Gives each place back its kind, and the Machine row's name and state
  # back to the settings.
  def self.convert_down
    add_kind_column unless connection.column_exists?(:locations, :kind)
    LocationType.reset_column_information
    connection.execute(<<~SQL.squish)
      UPDATE locations SET kind = CASE WHEN location_types.holds_installed_parts THEN 'machine' ELSE 'storage' END
      FROM location_types WHERE location_types.id = locations.location_type_id
    SQL
    machine = LocationType.find_by(key: "machine")
    return unless machine

    store_setting(:inventory_machines, machine.active ? "on" : "off")
    renamed = machine.name != "Machine"
    store_setting(:inventory_machine_name, renamed ? machine.name : "")
    store_setting(:inventory_machine_name_plural, renamed || machine.plural != "Machines" ? machine.plural.to_s : "")
  end

  def self.seed_defaults
    return if LocationType.exists?

    DEFAULTS.each_with_index { |row, index| LocationType.create!(row.merge(position: index)) }
  end

  def self.find_or_create_by_name(name)
    LocationType.where("LOWER(name) = ?", name.downcase).first ||
      LocationType.create!(name: name, position: LocationType.maximum(:position).to_i + 1)
  end

  def self.add_kind_column
    connection.add_column :locations, :kind, :string, null: false, default: "storage"
  end

  def self.connection
    ActiveRecord::Base.connection
  end

  def self.sanitize(sql)
    ActiveRecord::Base.sanitize_sql_array(sql)
  end

  def self.stored_setting(key)
    Settings.instance.stored_values[key] if defined?(Settings)
  end

  def self.store_setting(key, value)
    return unless defined?(Settings)

    store = Settings.instance.store
    store.transaction { store[key] = value }
  end
end
