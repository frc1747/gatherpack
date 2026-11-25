# Reading types (inventory spec §3.15): a managed list of what a check can
# record, such as Hours (h). Items pick the types they track
# (item_reading_types) instead of typing { name, unit } into
# items.reading_fields. Every name and unit already typed becomes a row,
# one per name and unit; a name already taken with another unit gets the
# unit added to it ("Hours (min)"), since names are unique. Readings stored
# on checks are keyed by the reading type's id instead of its name.
class CreateReadingTypes < ActiveRecord::Migration[8.1]
  class ReadingType < ActiveRecord::Base
    self.table_name = "reading_types"
  end

  class Item < ActiveRecord::Base
    self.table_name = "items"
  end

  class ItemUnitEvent < ActiveRecord::Base
    self.table_name = "item_unit_events"
  end

  DEFAULTS = [
    { name: "Hours", plural: "Hours", key: "hours", unit_label: "h" },
    { name: "Cycles", plural: "Cycles", key: "cycles" },
    { name: "Volts", plural: "Volts", key: "volts", unit_label: "V" }
  ].freeze

  def change
    create_table :reading_types, id: :uuid do |t|
      t.string :name, null: false
      t.string :plural
      t.string :key
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :unit_label
      t.timestamps
    end
    add_index :reading_types, "lower(name)", unique: true
    add_index :reading_types, :key, unique: true

    create_table :item_reading_types, id: :uuid do |t|
      t.references :item, null: false, foreign_key: true, type: :uuid, index: false
      t.references :reading_type, null: false, foreign_key: true, type: :uuid
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :item_reading_types, %i[item_id reading_type_id], unique: true

    reversible do |dir|
      dir.up { self.class.convert_up }
      dir.down { self.class.convert_down }
    end

    remove_column :items, :reading_fields, :jsonb, null: false, default: []
  end

  def self.convert_up
    [ ReadingType, Item, ItemUnitEvent ].each(&:reset_column_information)
    seed_defaults
    now = Time.current
    types_by_item = {}
    Item.where("jsonb_array_length(reading_fields) > 0").order(:created_at, :name, :id).each do |item|
      types = types_by_item[item.id] = {}
      Array(item.reading_fields).each_with_index do |field, index|
        next if field["name"].to_s.strip.empty?

        type = type_for(field["name"], field["unit"])
        linked = types.value?(type.id)
        types[field["name"].to_s.strip] = type.id
        next if linked

        connection.execute(sanitize([ "INSERT INTO item_reading_types (item_id, reading_type_id, position, created_at, updated_at) " \
          "VALUES (?, ?, ?, ?, ?)", item.id, type.id, index, now, now ]))
      end
    end

    ItemUnitEvent.where("readings <> '{}'::jsonb").find_each do |event|
      item_id = connection.select_value(sanitize([ "SELECT item_id FROM item_units WHERE id = ?", event.item_unit_id ]))
      types = types_by_item.fetch(item_id, {})
      keyed = event.readings.to_h.to_h { |name, value| [ types[name.to_s.strip] || type_for(name, nil).id, value ] }
      event.update_columns(readings: keyed)
    end
  end

  # Items get their readings back as names and units, and checks their
  # readings keyed by name.
  def self.convert_down
    connection.add_column :items, :reading_fields, :jsonb, null: false, default: [] unless connection.column_exists?(:items, :reading_fields)
    [ ReadingType, Item, ItemUnitEvent ].each(&:reset_column_information)
    types = ReadingType.all.index_by(&:id)
    rows = connection.select_rows("SELECT item_id, reading_type_id FROM item_reading_types ORDER BY item_id, position")
    rows.group_by(&:first).each do |item_id, links|
      fields = links.filter_map { |_, type_id| types[type_id] }.map { |type| { "name" => type.name, "unit" => type.unit_label.presence }.compact }
      Item.where(id: item_id).update_all(reading_fields: fields)
    end
    ItemUnitEvent.where("readings <> '{}'::jsonb").find_each do |event|
      named = event.readings.to_h.to_h { |id, value| [ types[id]&.name || id, value ] }
      event.update_columns(readings: named)
    end
  end

  def self.seed_defaults
    return if ReadingType.exists?

    DEFAULTS.each_with_index { |row, index| ReadingType.create!(row.merge(position: index)) }
  end

  # The row with this name and unit (ignoring case), or a new one. A name
  # another unit already has takes its unit in brackets.
  def self.type_for(name, unit)
    name = name.to_s.strip
    unit = unit.to_s.strip.presence
    found = ReadingType.where("LOWER(name) = ?", name.downcase).first
    return found if found && found.unit_label.to_s.casecmp?(unit.to_s)

    if found
      name = "#{name} (#{unit || "no unit"})"
      again = ReadingType.where("LOWER(name) = ?", name.downcase).first
      return again if again
    end
    ReadingType.create!(name: name, unit_label: unit, position: ReadingType.maximum(:position).to_i + 1)
  end

  def self.connection
    ActiveRecord::Base.connection
  end

  def self.sanitize(sql)
    ActiveRecord::Base.sanitize_sql_array(sql)
  end
end
