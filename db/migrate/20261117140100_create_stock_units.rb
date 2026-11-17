# Stock units (inventory spec §3.1): a managed list that replaces the text
# in items.unit. Every unit already typed on an item becomes a row (matched
# to a default by name or plural, ignoring case), and the
# inventory_default_unit setting picks the default row. Exactly one row is
# the default. The setting is left in the store for a rollback.
class CreateStockUnits < ActiveRecord::Migration[8.1]
  class StockUnit < ActiveRecord::Base
    self.table_name = "stock_units"
  end

  DEFAULTS = [
    { name: "each", plural: "each", key: "each", default: true },
    { name: "box", plural: "boxes" },
    { name: "pack", plural: "packs" },
    { name: "roll", plural: "rolls" },
    { name: "foot", plural: "feet" },
    { name: "set", plural: "sets" }
  ].freeze

  def change
    create_table :stock_units, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.boolean :default, null: false, default: false
      t.timestamps
    end
    add_index :stock_units, "lower(name)", unique: true
    add_index :stock_units, :key, unique: true
    add_index :stock_units, :default, unique: true, where: "\"default\"", name: "index_stock_units_one_default"
    add_reference :items, :stock_unit, type: :uuid, foreign_key: true

    reversible do |dir|
      dir.up { self.class.convert_up }
      dir.down { self.class.convert_down }
    end

    change_column_null :items, :stock_unit_id, false
    remove_column :items, :unit, :string, null: false, default: "each"
  end

  def self.convert_up
    StockUnit.reset_column_information
    seed_defaults
    connection.select_values("SELECT DISTINCT unit FROM items WHERE unit IS NOT NULL").each do |text|
      row = unit_for(text)
      connection.execute(sanitize([ "UPDATE items SET stock_unit_id = ? WHERE unit = ?", row.id, text ]))
    end

    default_text = stored_setting(:inventory_default_unit).to_s
    if default_text.strip.present?
      default = unit_for(default_text)
      StockUnit.transaction do
        StockUnit.where.not(id: default.id).update_all(default: false)
        default.update!(default: true, active: true)
      end
    end
    each = StockUnit.find_by(default: true)
    connection.execute(sanitize([ "UPDATE items SET stock_unit_id = ? WHERE stock_unit_id IS NULL", each.id ]))
  end

  # Items get their unit's name back, and the default row goes back into
  # the setting.
  def self.convert_down
    connection.add_column :items, :unit, :string, null: false, default: "each" unless connection.column_exists?(:items, :unit)
    connection.execute(<<~SQL.squish)
      UPDATE items SET unit = stock_units.name FROM stock_units WHERE stock_units.id = items.stock_unit_id
    SQL
    StockUnit.reset_column_information
    default = StockUnit.find_by(default: true)
    store_setting(:inventory_default_unit, default.name) if default
  end

  def self.seed_defaults
    return if StockUnit.exists?

    DEFAULTS.each_with_index { |row, index| StockUnit.create!(row.merge(position: index)) }
  end

  # The row named (or pluralized) as the text, ignoring case and spaces, or
  # a new one at the end.
  def self.unit_for(text)
    name = text.to_s.strip
    name = "each" if name.empty?
    StockUnit.where("LOWER(name) = :n OR LOWER(plural) = :n", n: name.downcase).order(:position).first ||
      StockUnit.create!(name: name, position: StockUnit.maximum(:position).to_i + 1)
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
